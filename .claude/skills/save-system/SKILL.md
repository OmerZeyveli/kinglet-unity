---
name: save-system
description: "Save/load patterns — ISaveable interface, JSON serialization, save file management, scene persistence, cloud sync prep. Load when implementing save functionality."
---

# Save/Load System

> **The examples below are written in this toolkit's default stack** (VContainer registration,
> `UniTask` for async). Whether that stack binds in *this* project is stated in `CLAUDE.md`'s
> generated block, detected from the code. Where it does not bind, take the **structure** from
> this skill and express it in the architecture the project actually has — do not introduce
> VContainer, MessagePipe or UniTask to a project that does not already use them, and do not
> conclude the skill is inapplicable.

*Written against Unity 6000.0, current as of 2026-08-04.*

## Boundary with the rules

`.claude/rules/serialization.md` binds `[FormerlySerializedAs]` on any renamed serialized field and
the Unity `== null` check for destroyed-object detection. This skill carries save-file format, slot
management, scene persistence, and version migration on top of that binding — a save-data class is
still Unity-serialized data and the rename rule applies to it the same as any other field. Two more
rules also bind here and previously went uncited: `architecture.md` §No Singletons (VContainer
registration replaces every `static Instance` pattern) and `unity-specifics.md` §No Coroutines (UniTask
replaces `StartCoroutine`/`IEnumerator`/`yield return` entirely). `SaveManager` below is written to
those two rules — a plain C# class registered `Lifetime.Singleton` in a `LifetimeScope`, injected
into the Views that call it, with the scene-load wait expressed as `UniTask` — not the
`MonoBehaviour Instance` + coroutine shape this pattern carries in most Unity tutorials. Where this
skill and any of the three rules disagree, the rule wins and this skill is what is out of date.

Patterns for persisting game state to disk: an ISaveable interface for components that need persistence, a central SaveManager that orchestrates capture and restore, JSON serialization, save slot management, and preparation for cloud sync.

## ISaveable Interface

Every component that needs to save state implements this interface. The SaveManager discovers all ISaveable objects in the scene and calls them during save/load.

```csharp
/// <summary>
/// Implement on any MonoBehaviour that needs to persist state across saves.
/// </summary>
public interface ISaveable
{
    /// <summary>
    /// Unique key for this saveable. Must be stable across sessions.
    /// Recommended format: "{scene}_{gameobject}_{component}" or a GUID.
    /// </summary>
    string SaveKey { get; }

    /// <summary>
    /// Capture current state as a serializable object.
    /// Return a plain C# class or struct (no MonoBehaviour, no ScriptableObject).
    /// </summary>
    object CaptureState();

    /// <summary>
    /// Restore state from a previously captured object.
    /// Cast the object to the expected type.
    /// </summary>
    void RestoreState(object state);
}
```

### Example: Saveable Health Component

```csharp
using UnityEngine;

public class Health : MonoBehaviour, ISaveable
{
    [SerializeField] private int maxHealth = 100;
    [SerializeField] private string saveKey;

    private int _currentHealth;

    public string SaveKey => saveKey;

    private void Awake()
    {
        _currentHealth = maxHealth;
    }

    [System.Serializable]
    private struct HealthSaveData
    {
        public int currentHealth;
        public int maxHealth;
    }

    public object CaptureState()
    {
        return new HealthSaveData
        {
            currentHealth = _currentHealth,
            maxHealth = maxHealth
        };
    }

    public void RestoreState(object state)
    {
        if (state is HealthSaveData data)
        {
            _currentHealth = data.currentHealth;
            maxHealth = data.maxHealth;
        }
    }
}
```

### Generating Stable Save Keys

The save key must be the same every time the game runs. Options:

1. **Manual string** (simplest): Assign in Inspector. Works for unique objects like "player_health".
2. **GUID component:** Add a `SaveableEntity` MonoBehaviour with a `[SerializeField] private string uniqueId` that generates a GUID in `Reset()` (called when the component is first added in the editor). This auto-generates stable IDs.

```csharp
using UnityEngine;

public class SaveableEntity : MonoBehaviour
{
    [SerializeField] private string uniqueId;

    public string UniqueId => uniqueId;

    // Called in editor when component is first added
    private void Reset()
    {
        uniqueId = System.Guid.NewGuid().ToString();
    }
}
```

---

## Save Data Structure

A single save file contains all captured state, plus metadata.

```csharp
using System;
using System.Collections.Generic;

[Serializable]
public class SaveData
{
    public int saveVersion = 1;
    public string timestamp;
    public string sceneName;
    public float playTime;

    // All saveable state, keyed by ISaveable.SaveKey
    // Values are JSON strings (serialized individually per saveable)
    public Dictionary<string, string> stateEntries = new();
}
```

Using `Dictionary<string, string>` where values are JSON strings (rather than `Dictionary<string, object>`) avoids polymorphic serialization issues with `JsonUtility`. Each ISaveable's state is serialized independently.

---

## Save Manager

The central orchestrator. Finds all ISaveable components, serializes their state, and writes to disk.

Plain C# System, not a `MonoBehaviour` singleton — registered once as `Lifetime.Singleton` in a
`LifetimeScope` and injected into whatever View or System needs it. No `static Instance`, no
`DontDestroyOnLoad`: a `Lifetime.Singleton` registration in the root scope already survives scene
loads the same way, without the null-check-in-Awake dance a `static Instance` needs.

```csharp
using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using Cysharp.Threading.Tasks;
using UnityEngine;
using UnityEngine.SceneManagement;

public sealed class SaveManager
{
    private readonly int _maxSaveSlots;
    // Not readonly: RestoreState reassigns it when a save is loaded, so the session clock
    // continues from the saved playtime rather than from process start.
    private float _sessionStartTime;

    public event Action OnSaveCompleted;
    public event Action OnLoadCompleted;

    public SaveManager(int maxSaveSlots = 3)
    {
        _maxSaveSlots = maxSaveSlots;
        _sessionStartTime = Time.time;
    }

    // --- File Paths ---

    private string GetSaveFolderPath()
    {
        return Path.Combine(Application.persistentDataPath, "Saves");
    }

    private string GetSaveFilePath(int slot)
    {
        return Path.Combine(GetSaveFolderPath(), $"Save{slot}.json");
    }

    private string GetAutoSaveFilePath()
    {
        return Path.Combine(GetSaveFolderPath(), "AutoSave.json");
    }

    // --- Save ---

    public void Save(int slot)
    {
        SaveToFile(GetSaveFilePath(slot));
    }

    public void AutoSave()
    {
        SaveToFile(GetAutoSaveFilePath());
    }

    private void SaveToFile(string path)
    {
        var saveData = new SaveData
        {
            saveVersion = 1,
            timestamp = DateTime.Now.ToString("o"),
            sceneName = SceneManager.GetActiveScene().name,
            playTime = Time.time - _sessionStartTime
        };

        // Find all saveables in the scene
        var saveables = FindAllSaveables();

        foreach (var saveable in saveables)
        {
            try
            {
                object state = saveable.CaptureState();
                string json = JsonUtility.ToJson(state);
                saveData.stateEntries[saveable.SaveKey] = json;
            }
            catch (Exception e)
            {
                Debug.LogError($"Failed to capture state for {saveable.SaveKey}: {e.Message}");
            }
        }

        // Serialize the full save data
        // Using Newtonsoft because JsonUtility cannot serialize Dictionary
        string fullJson = Newtonsoft.Json.JsonConvert.SerializeObject(saveData, Newtonsoft.Json.Formatting.Indented);

        // Ensure directory exists
        Directory.CreateDirectory(Path.GetDirectoryName(path));

        // Write atomically: write to temp file, then rename
        string tempPath = path + ".tmp";
        File.WriteAllText(tempPath, fullJson);
        if (File.Exists(path)) File.Delete(path);
        File.Move(tempPath, path);

        Debug.Log($"Game saved to {path}");
        OnSaveCompleted?.Invoke();
    }

    // --- Load ---

    public UniTask LoadAsync(int slot, CancellationToken token = default)
    {
        return LoadFromFileAsync(GetSaveFilePath(slot), token);
    }

    public UniTask LoadAutoSaveAsync(CancellationToken token = default)
    {
        return LoadFromFileAsync(GetAutoSaveFilePath(), token);
    }

    private async UniTask LoadFromFileAsync(string path, CancellationToken token)
    {
        if (!File.Exists(path))
        {
            Debug.LogWarning($"Save file not found: {path}");
            return;
        }

        string json = File.ReadAllText(path);
        var saveData = Newtonsoft.Json.JsonConvert.DeserializeObject<SaveData>(json);

        if (saveData == null)
        {
            Debug.LogError("Failed to deserialize save data.");
            return;
        }

        // Handle version migration
        if (saveData.saveVersion < 1)
        {
            MigrateSaveData(saveData);
        }

        // Load the correct scene, then restore state
        if (SceneManager.GetActiveScene().name != saveData.sceneName)
        {
            await LoadSceneThenRestoreAsync(saveData, token);
        }
        else
        {
            RestoreState(saveData);
        }
    }

    private async UniTask LoadSceneThenRestoreAsync(SaveData saveData, CancellationToken token)
    {
        await SceneManager.LoadSceneAsync(saveData.sceneName).ToUniTask(cancellationToken: token);

        // Wait one frame for scene objects to initialize
        await UniTask.Yield(token);

        RestoreState(saveData);
    }

    private void RestoreState(SaveData saveData)
    {
        var saveables = FindAllSaveables();

        foreach (var saveable in saveables)
        {
            if (!saveData.stateEntries.TryGetValue(saveable.SaveKey, out string json))
                continue;

            try
            {
                // The saveable knows its own state type.
                // We pass the raw JSON string; the saveable deserializes it.
                saveable.RestoreState(json);
            }
            catch (Exception e)
            {
                Debug.LogError($"Failed to restore state for {saveable.SaveKey}: {e.Message}");
            }
        }

        _sessionStartTime = Time.time - saveData.playTime;
        OnLoadCompleted?.Invoke();
        Debug.Log("Game loaded successfully.");
    }

    // --- Query ---

    public bool SaveExists(int slot) => File.Exists(GetSaveFilePath(slot));
    public bool AutoSaveExists() => File.Exists(GetAutoSaveFilePath());

    public SaveData GetSaveMetadata(int slot)
    {
        string path = GetSaveFilePath(slot);
        if (!File.Exists(path)) return null;

        string json = File.ReadAllText(path);
        return Newtonsoft.Json.JsonConvert.DeserializeObject<SaveData>(json);
    }

    public void DeleteSave(int slot)
    {
        string path = GetSaveFilePath(slot);
        if (File.Exists(path)) File.Delete(path);
    }

    // --- Helpers ---

    private List<ISaveable> FindAllSaveables()
    {
        var result = new List<ISaveable>();
        // FindObjectsOfType does not find interfaces directly, so find all MonoBehaviours
        // and filter. For better performance, maintain a registry (see below).
        foreach (var mb in FindObjectsOfType<MonoBehaviour>(true))
        {
            if (mb is ISaveable saveable)
                result.Add(saveable);
        }
        return result;
    }

    private void MigrateSaveData(SaveData data)
    {
        // Example: migrate from version 0 to version 1
        // Add new fields, rename keys, transform data
        data.saveVersion = 1;
        Debug.Log("Migrated save data to version 1.");
    }
}
```

Registered once, in the scope that should own it for the session (usually `RootLifetimeScope` — save
data outlives any single scene):

```csharp
protected override void Configure(IContainerBuilder builder)
{
    builder.Register<SaveManager>(Lifetime.Singleton);
    builder.Register<AutoSaveSystem>(Lifetime.Singleton);
}
```

### Alternative: ISaveable with JSON String

If you prefer to avoid the `object` cast pattern, have `RestoreState` accept a JSON string directly:

```csharp
public interface ISaveable
{
    string SaveKey { get; }
    string CaptureStateJson();
    void RestoreStateJson(string json);
}

// Implementation:
public string CaptureStateJson()
{
    return JsonUtility.ToJson(new HealthSaveData
    {
        currentHealth = _currentHealth,
        maxHealth = maxHealth
    });
}

public void RestoreStateJson(string json)
{
    var data = JsonUtility.FromJson<HealthSaveData>(json);
    _currentHealth = data.currentHealth;
    maxHealth = data.maxHealth;
}
```

This avoids boxing and unboxing, making the type contract clearer.

---

## JSON Serialization: JsonUtility vs Newtonsoft

**JsonUtility (built-in):**
- Fast, no external dependency
- Cannot serialize Dictionary, polymorphic types, or properties
- Only serializes fields (public or `[SerializeField]`)
- No pretty-print option
- Use for: individual component state (simple structs)

**Newtonsoft Json.NET (via `com.unity.nuget.newtonsoft-json`):**
- Full-featured: Dictionary, polymorphism, properties, custom converters
- Slower than JsonUtility
- Required for the SaveData wrapper (contains Dictionary)
- Install via Package Manager: `com.unity.nuget.newtonsoft-json`

**Strategy:** Use JsonUtility for individual ISaveable state capture (fast, simple structs). Use Newtonsoft for the top-level SaveData that aggregates everything (needs Dictionary support).

---

## Save File Management

### Save Slots UI

```csharp
using UnityEngine;
using TMPro;

// View — SaveManager is injected, never reached through a static Instance.
public sealed class SaveSlotUI : MonoBehaviour
{
    [SerializeField] private int _slotIndex;
    [SerializeField] private TextMeshProUGUI _slotInfoText;
    [SerializeField] private GameObject _emptyLabel;
    [SerializeField] private GameObject _dataPanel;

    private SaveManager _saveManager;

    [Inject]
    public void Construct(SaveManager saveManager)
    {
        _saveManager = saveManager;
    }

    private void OnEnable()
    {
        RefreshDisplay();
    }

    public void RefreshDisplay()
    {
        bool exists = _saveManager.SaveExists(_slotIndex);
        _emptyLabel.SetActive(!exists);
        _dataPanel.SetActive(exists);

        if (exists)
        {
            var metadata = _saveManager.GetSaveMetadata(_slotIndex);
            if (metadata != null)
            {
                var time = System.DateTime.Parse(metadata.timestamp);
                _slotInfoText.text = $"{metadata.sceneName}\n{time:yyyy-MM-dd HH:mm}";
            }
        }
    }

    public void OnSaveClicked() => _saveManager.Save(_slotIndex);
    public void OnLoadClicked() => _saveManager.LoadAsync(_slotIndex, this.GetCancellationTokenOnDestroy()).Forget();
    public void OnDeleteClicked() => _saveManager.DeleteSave(_slotIndex);
}
```

---

## Auto-Save

Trigger auto-save on meaningful events rather than a fixed timer. This avoids saving in the middle of combat or dialogue.

```csharp
// System — owns the auto-save cadence, calls the injected SaveManager. Not a MonoBehaviour: nothing
// here needs a scene presence, and a plain class registered Lifetime.Singleton is the whole pattern.
public sealed class AutoSaveSystem
{
    private readonly SaveManager _saveManager;
    private readonly float _minTimeBetweenAutoSaves;

    private float _lastAutoSaveTime;

    public AutoSaveSystem(SaveManager saveManager, float minTimeBetweenAutoSaves = 60f)
    {
        _saveManager = saveManager;
        _minTimeBetweenAutoSaves = minTimeBetweenAutoSaves;
    }

    /// <summary>
    /// Call from checkpoint triggers, level transitions, etc.
    /// </summary>
    public void TriggerAutoSave()
    {
        if (Time.time - _lastAutoSaveTime < _minTimeBetweenAutoSaves) return;

        _saveManager.AutoSave();
        _lastAutoSaveTime = Time.time;
    }
}
```

Good auto-save triggers:
- Entering a new area or room
- Reaching a checkpoint
- Completing a quest objective
- After a shop transaction
- Before a boss fight (so the player does not lose progress)

---

## Scene Persistence

What survives scene loads?

**DontDestroyOnLoad objects:** Player stats, inventory, quest state. These live on a persistent GameObject.

**Per-scene state:** Enemy positions, opened chests, broken walls. Save these per-scene in the SaveData. Use the scene name as a prefix in save keys: `"forest_chest_01"`, `"dungeon_enemy_03"`.

**Transient state:** Particle effects, UI animations, temporary projectiles. Never save these.

```csharp
// Pattern for per-scene state that persists after leaving and returning:
public class DestroyedObjectTracker : MonoBehaviour, ISaveable
{
    [SerializeField] private string saveKey;
    [SerializeField] private GameObject[] destroyableObjects;

    private HashSet<int> _destroyedIndices = new();

    public string SaveKey => saveKey;

    public void MarkDestroyed(int index)
    {
        _destroyedIndices.Add(index);
        if (index >= 0 && index < destroyableObjects.Length)
            destroyableObjects[index].SetActive(false);
    }

    [System.Serializable]
    private struct TrackerSaveData { public int[] destroyedIndices; }

    public object CaptureState()
    {
        return new TrackerSaveData { destroyedIndices = new List<int>(_destroyedIndices).ToArray() };
    }

    public void RestoreState(object state)
    {
        if (state is string json)
        {
            var data = JsonUtility.FromJson<TrackerSaveData>(json);
            _destroyedIndices = new HashSet<int>(data.destroyedIndices);
            foreach (int i in _destroyedIndices)
            {
                if (i >= 0 && i < destroyableObjects.Length)
                    destroyableObjects[i].SetActive(false);
            }
        }
    }
}
```

---

## PlayerPrefs: Settings Only

Use `PlayerPrefs` exclusively for non-gameplay settings:
- Audio volume (master, music, SFX)
- Graphics quality level
- Resolution and fullscreen toggle
- Language preference
- Control sensitivity

Never store game progress, inventory, or quest state in PlayerPrefs. It is not designed for structured data, has platform-specific size limits, and is trivially editable by players.

```csharp
public static class SettingsManager
{
    public static float MasterVolume
    {
        get => PlayerPrefs.GetFloat("Settings_MasterVolume", 1f);
        set { PlayerPrefs.SetFloat("Settings_MasterVolume", value); PlayerPrefs.Save(); }
    }

    public static int QualityLevel
    {
        get => PlayerPrefs.GetInt("Settings_QualityLevel", QualitySettings.GetQualityLevel());
        set { PlayerPrefs.SetInt("Settings_QualityLevel", value); QualitySettings.SetQualityLevel(value); PlayerPrefs.Save(); }
    }

    public static bool IsFullscreen
    {
        get => PlayerPrefs.GetInt("Settings_Fullscreen", 1) == 1;
        set { PlayerPrefs.SetInt("Settings_Fullscreen", value ? 1 : 0); Screen.fullScreen = value; PlayerPrefs.Save(); }
    }
}
```

---

## Cloud Sync Preparation

If you plan to support cloud saves (Steam Cloud, platform cloud storage):

1. **Save to a known, flat directory.** Steam Cloud syncs specific paths. Keep all save files in `Application.persistentDataPath/Saves/`.
2. **Keep file sizes small.** Cloud sync has bandwidth limits. Avoid saving large binary blobs.
3. **Include a timestamp in metadata.** Cloud conflict resolution needs to know which save is newer.
4. **Design for conflict resolution.** When local and cloud saves differ, present the player with a choice: "Use local save (2 hours ahead) or cloud save (from another device)?"
5. **Test offline behavior.** The game must work when cloud sync fails. Always fall back to local saves.

---

## Version Migration

Add a version number to every save file. When the save format changes (new fields, renamed keys, restructured data), increment the version and write migration logic.

```csharp
private SaveData MigrateSaveData(SaveData data)
{
    // Migration chain: apply each migration in order
    if (data.saveVersion < 1)
    {
        // v0 -> v1: Added playTime field
        data.playTime = 0f;
        data.saveVersion = 1;
    }

    if (data.saveVersion < 2)
    {
        // v1 -> v2: Renamed "player_hp" key to "player_health"
        if (data.stateEntries.ContainsKey("player_hp"))
        {
            data.stateEntries["player_health"] = data.stateEntries["player_hp"];
            data.stateEntries.Remove("player_hp");
        }
        data.saveVersion = 2;
    }

    return data;
}
```

Never break backward compatibility. Always migrate forward. Players who return after months should not lose their saves.

---

## Encryption for Anti-Cheat

For release builds, encrypt save files to discourage casual editing. This is not bulletproof security; it just raises the effort threshold.

```csharp
using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

public static class SaveEncryption
{
    // In production, derive this from a machine-specific value or obfuscate it
    private static readonly byte[] Key = Encoding.UTF8.GetBytes("YourGame16ByteK"); // 16 bytes for AES-128
    private static readonly byte[] IV = Encoding.UTF8.GetBytes("YourGameIV128bit");  // 16 bytes

    public static string Encrypt(string plainText)
    {
        using var aes = Aes.Create();
        aes.Key = Key;
        aes.IV = IV;

        using var encryptor = aes.CreateEncryptor();
        byte[] plainBytes = Encoding.UTF8.GetBytes(plainText);
        byte[] encrypted = encryptor.TransformFinalBlock(plainBytes, 0, plainBytes.Length);
        return Convert.ToBase64String(encrypted);
    }

    public static string Decrypt(string cipherText)
    {
        using var aes = Aes.Create();
        aes.Key = Key;
        aes.IV = IV;

        using var decryptor = aes.CreateDecryptor();
        byte[] cipherBytes = Convert.FromBase64String(cipherText);
        byte[] decrypted = decryptor.TransformFinalBlock(cipherBytes, 0, cipherBytes.Length);
        return Encoding.UTF8.GetString(decrypted);
    }
}
```

Use encryption only in release builds. Keep saves as readable JSON during development for debugging.

---

## Practical Tips

- **Atomic writes:** Always write to a temporary file first, then rename. If the game crashes mid-write, the original save is preserved.
- **Backup previous save:** Before overwriting, copy the existing file to `Save1.json.bak`. One-level backup catches most corruption scenarios.
- **Test save/load early and often.** Retrofitting save support into a mature codebase is painful. Implement ISaveable on each component as you build it.
- **Save file size monitoring:** Log save file sizes during development. If a save grows unexpectedly large, you are probably serializing something you should not be (mesh data, texture references).
- **Deterministic save keys:** If you use GUIDs, generate them in the editor (not at runtime). Runtime-generated GUIDs change every session and break save/load.
