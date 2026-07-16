---
name: scriptable-objects
description: "ScriptableObject architecture patterns — event channels, variable references, runtime sets, factory pattern, data containers. The backbone of data-driven Unity architecture."
alwaysApply: true
---

# ScriptableObject Architecture

ScriptableObjects (SOs) are Unity's most powerful architectural tool. They are asset-based data containers that live outside scenes, enabling data-driven design, loose coupling, and designer-friendly workflows.

## Pattern 1: Data Container

The simplest and most common use — define game data as assets.

```csharp
[CreateAssetMenu(fileName = "NewWeapon", menuName = "Game/Weapon Definition")]
public sealed class WeaponDefinition : ScriptableObject
{
    [Header("Identity")]
    [SerializeField] private string _displayName;
    [SerializeField] private Sprite _icon;
    [TextArea]
    [SerializeField] private string _description;

    [Header("Stats")]
    [SerializeField] private float _damage = 10f;
    [SerializeField] private float _fireRate = 0.5f;
    [SerializeField] private int _ammoCapacity = 30;
    [SerializeField] private GameObject _prefab;

    public string DisplayName => _displayName;
    public Sprite Icon => _icon;
    public float Damage => _damage;
    public float FireRate => _fireRate;
    public int AmmoCapacity => _ammoCapacity;
    public GameObject Prefab => _prefab;
}
```

**Use for:** Items, abilities, enemy configs, level data, audio events, UI themes.

## Pattern 2: Event Channel

Zero-coupling communication between systems. No direct references needed.

```csharp
[CreateAssetMenu(fileName = "NewVoidEvent", menuName = "Events/Void Event")]
public sealed class VoidEventChannel : ScriptableObject
{
    private System.Action _onRaised;

    public void Raise()
    {
        _onRaised?.Invoke();
    }

    public void Subscribe(System.Action listener)
    {
        _onRaised += listener;
    }

    public void Unsubscribe(System.Action listener)
    {
        _onRaised -= listener;
    }
}

// Generic version for typed events
[CreateAssetMenu(fileName = "NewIntEvent", menuName = "Events/Int Event")]
public sealed class IntEventChannel : ScriptableObject
{
    private System.Action<int> _onRaised;

    public void Raise(int value) => _onRaised?.Invoke(value);
    public void Subscribe(System.Action<int> listener) => _onRaised += listener;
    public void Unsubscribe(System.Action<int> listener) => _onRaised -= listener;
}
```

**Usage:**
```csharp
// Publisher (e.g., ScoreSystem)
[SerializeField] private IntEventChannel _onScoreChanged;
_onScoreChanged.Raise(newScore);

// Subscriber (e.g., ScoreUI) — wire the SAME SO asset in inspector
[SerializeField] private IntEventChannel _onScoreChanged;
private void OnEnable() => _onScoreChanged.Subscribe(UpdateDisplay);
private void OnDisable() => _onScoreChanged.Unsubscribe(UpdateDisplay);
```

## Pattern 3: Variable Reference

Inspector-tweakable values that can be shared or overridden per instance.

```csharp
[System.Serializable]
public sealed class FloatReference
{
    [SerializeField] private bool _useConstant = true;
    [SerializeField] private float _constantValue;
    [SerializeField] private FloatVariable _variable;

    public float Value => _useConstant ? _constantValue : _variable.Value;
}

[CreateAssetMenu(fileName = "NewFloatVar", menuName = "Variables/Float")]
public sealed class FloatVariable : ScriptableObject
{
    [SerializeField] private float _value;
    public float Value { get => _value; set => _value = value; }
}
```

**Use for:** Player health, move speed, gravity — values that designers tweak and multiple systems read.

## Pattern 4: Runtime Set

Track all active instances of a type without FindObjectsOfType.

```csharp
[CreateAssetMenu(fileName = "NewRuntimeSet", menuName = "Sets/Transform Set")]
public sealed class TransformRuntimeSet : ScriptableObject
{
    private readonly List<Transform> _items = new();

    public IReadOnlyList<Transform> Items => _items;
    public int Count => _items.Count;

    public void Add(Transform item)
    {
        if (!_items.Contains(item))
        {
            _items.Add(item);
        }
    }

    public void Remove(Transform item)
    {
        _items.Remove(item);
    }
}

// Usage: enemies register themselves
public sealed class Enemy : MonoBehaviour
{
    [SerializeField] private TransformRuntimeSet _enemySet;

    private void OnEnable() => _enemySet.Add(transform);
    private void OnDisable() => _enemySet.Remove(transform);
}
```

## Pattern 5: Factory Configuration

```csharp
[CreateAssetMenu(fileName = "NewSpawnConfig", menuName = "Game/Spawn Config")]
public sealed class SpawnConfiguration : ScriptableObject
{
    [SerializeField] private GameObject _prefab;
    [SerializeField] private int _poolSize = 10;
    [SerializeField] private float _spawnRate = 2f;
    [SerializeField] private float _spawnRadius = 15f;

    public GameObject Prefab => _prefab;
    public int PoolSize => _poolSize;
    public float SpawnRate => _spawnRate;
    public float SpawnRadius => _spawnRadius;
}
```

## Anti-Patterns

1. **Mutable state not reset between plays** — SOs persist across play sessions in Editor. If you write to an SO at runtime, it keeps the value when you stop playing. Use `OnEnable` or `OnDisable` to reset, or use a separate runtime copy.

2. **SO as singleton** — Don't use `Resources.Load` to access SOs globally. Use `[SerializeField]` references or DI.

3. **Too much logic in SOs** — SOs are data and events. Keep complex logic in systems/services.

4. **Circular SO references** — SO A references SO B which references SO A. Can cause infinite loops in serialization.
