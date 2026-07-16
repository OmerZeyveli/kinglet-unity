---
name: dialogue-system
description: "Dialogue tree patterns — ScriptableObject graph, node types (text, choice, condition, event), typewriter effect, localization-ready. Load when implementing NPC conversations."
globs: ["**/Dialogue*.cs", "**/Conversation*.cs", "**/NPC*.cs"]
---

# Dialogue System

Patterns for building a node-based dialogue tree system: define conversations as ScriptableObject graphs, process them at runtime with a DialogueRunner, display text with a typewriter effect, and integrate with quest/state systems through condition and event nodes.

## Node Architecture

Dialogue is a directed graph of nodes. Each node has a unique ID and a type that determines its behavior.

### Base Node

```csharp
using UnityEngine;

public enum DialogueNodeType
{
    Text,
    Choice,
    Condition,
    Event
}

[System.Serializable]
public class DialogueNode
{
    public string nodeId;
    public DialogueNodeType nodeType;

    // Text node fields
    public string speakerName;
    public string speakerKey;       // Localization key for speaker name
    public Sprite speakerPortrait;
    public string text;
    public string textKey;          // Localization key: "dialogue.npc_greeting.001"
    public string nextNodeId;

    // Choice node fields
    public DialogueChoice[] choices;

    // Condition node fields
    public string conditionKey;     // Game state variable to check
    public string trueNodeId;
    public string falseNodeId;

    // Event node fields
    public string eventName;        // Event to trigger
    public string eventParameter;
    public string eventNextNodeId;
}
```

### Choice Data

```csharp
[System.Serializable]
public class DialogueChoice
{
    public string choiceText;
    public string choiceKey;        // Localization key
    public string nextNodeId;

    // Optional: conditions for showing this choice
    public string requiredConditionKey;
    public bool hideIfUnavailable;  // false = show grayed out; true = hide entirely
}
```

### Dialogue Tree (ScriptableObject)

```csharp
using System.Collections.Generic;
using UnityEngine;

[CreateAssetMenu(fileName = "New Dialogue", menuName = "Dialogue/Dialogue Tree")]
public class DialogueTree : ScriptableObject
{
    public string dialogueId;
    public string entryNodeId;
    public List<DialogueNode> nodes = new();

    private Dictionary<string, DialogueNode> _lookup;

    public DialogueNode GetNode(string nodeId)
    {
        if (_lookup == null) BuildLookup();
        _lookup.TryGetValue(nodeId, out var node);
        return node;
    }

    public DialogueNode GetEntryNode()
    {
        return GetNode(entryNodeId);
    }

    private void BuildLookup()
    {
        _lookup = new Dictionary<string, DialogueNode>();
        foreach (var node in nodes)
        {
            if (string.IsNullOrEmpty(node.nodeId)) continue;
            _lookup[node.nodeId] = node;
        }
    }

    private void OnEnable()
    {
        _lookup = null; // Force rebuild on load
    }
}
```

---

## Speaker Definition

Keep speaker data (name, portrait variations, voice settings) in a separate ScriptableObject so multiple dialogues can share the same speaker.

```csharp
using UnityEngine;

[CreateAssetMenu(fileName = "New Speaker", menuName = "Dialogue/Speaker")]
public class SpeakerDefinition : ScriptableObject
{
    public string speakerId;
    public string displayName;
    public string nameLocKey;
    public Sprite defaultPortrait;
    public Sprite[] emotionPortraits;   // Index by enum: Happy, Sad, Angry, etc.
    public Color nameColor = Color.white;

    [Header("Voice")]
    public AudioClip talkSound;         // Blip sound per character
    public float talkPitch = 1f;
}

public enum SpeakerEmotion
{
    Neutral,
    Happy,
    Sad,
    Angry,
    Surprised,
    Thinking
}
```

---

## Dialogue Runner

The runtime component that processes the dialogue tree node by node. It mediates between the data (DialogueTree) and the presentation (DialogueUI).

```csharp
using System;
using System.Collections;
using UnityEngine;

public class DialogueRunner : MonoBehaviour
{
    public static DialogueRunner Instance { get; private set; }

    [SerializeField] private DialogueUI dialogueUI;

    private DialogueTree _currentTree;
    private DialogueNode _currentNode;
    private bool _isRunning;

    public bool IsRunning => _isRunning;

    public event Action OnDialogueStarted;
    public event Action OnDialogueEnded;

    private void Awake()
    {
        Instance = this;
    }

    /// <summary>
    /// Start a conversation from the beginning of the given tree.
    /// </summary>
    public void StartDialogue(DialogueTree tree)
    {
        if (_isRunning) return;

        _currentTree = tree;
        _isRunning = true;

        OnDialogueStarted?.Invoke();
        dialogueUI.Show();

        ProcessNode(_currentTree.GetEntryNode());
    }

    private void ProcessNode(DialogueNode node)
    {
        if (node == null)
        {
            EndDialogue();
            return;
        }

        _currentNode = node;

        switch (node.nodeType)
        {
            case DialogueNodeType.Text:
                ProcessTextNode(node);
                break;
            case DialogueNodeType.Choice:
                ProcessChoiceNode(node);
                break;
            case DialogueNodeType.Condition:
                ProcessConditionNode(node);
                break;
            case DialogueNodeType.Event:
                ProcessEventNode(node);
                break;
        }
    }

    private void ProcessTextNode(DialogueNode node)
    {
        string displayText = GetLocalizedText(node.textKey, node.text);
        string displayName = GetLocalizedText(node.speakerKey, node.speakerName);

        dialogueUI.ShowText(displayName, displayText, node.speakerPortrait);
    }

    private void ProcessChoiceNode(DialogueNode node)
    {
        // Filter choices based on conditions
        var availableChoices = new System.Collections.Generic.List<DialogueChoice>();

        foreach (var choice in node.choices)
        {
            if (!string.IsNullOrEmpty(choice.requiredConditionKey))
            {
                bool conditionMet = GameStateManager.Instance.CheckCondition(choice.requiredConditionKey);
                if (!conditionMet && choice.hideIfUnavailable)
                    continue;
            }

            availableChoices.Add(choice);
        }

        dialogueUI.ShowChoices(availableChoices, OnChoiceSelected);
    }

    private void ProcessConditionNode(DialogueNode node)
    {
        bool result = GameStateManager.Instance.CheckCondition(node.conditionKey);
        string nextId = result ? node.trueNodeId : node.falseNodeId;
        ProcessNode(_currentTree.GetNode(nextId));
    }

    private void ProcessEventNode(DialogueNode node)
    {
        // Fire a game event (quest update, give item, play animation, etc.)
        GameEventManager.Instance.TriggerEvent(node.eventName, node.eventParameter);

        ProcessNode(_currentTree.GetNode(node.eventNextNodeId));
    }

    /// <summary>
    /// Called by UI when the player advances past a text node.
    /// </summary>
    public void AdvanceDialogue()
    {
        if (_currentNode == null || _currentNode.nodeType != DialogueNodeType.Text) return;

        // If typewriter is still running, complete it instantly
        if (dialogueUI.IsTyping)
        {
            dialogueUI.CompleteTypewriter();
            return;
        }

        // Move to next node
        string nextId = _currentNode.nextNodeId;
        if (string.IsNullOrEmpty(nextId))
        {
            EndDialogue();
        }
        else
        {
            ProcessNode(_currentTree.GetNode(nextId));
        }
    }

    private void OnChoiceSelected(int choiceIndex)
    {
        if (_currentNode == null || _currentNode.nodeType != DialogueNodeType.Choice) return;

        var choice = _currentNode.choices[choiceIndex];
        ProcessNode(_currentTree.GetNode(choice.nextNodeId));
    }

    public void EndDialogue()
    {
        _isRunning = false;
        _currentTree = null;
        _currentNode = null;

        dialogueUI.Hide();
        OnDialogueEnded?.Invoke();
    }

    private string GetLocalizedText(string locKey, string fallback)
    {
        if (string.IsNullOrEmpty(locKey)) return fallback;

        // Replace with your localization system lookup
        // return LocalizationManager.Instance.GetText(locKey);
        return fallback; // Fallback until localization is implemented
    }
}
```

---

## Dialogue UI

The presentation layer: text panel, speaker name, portrait, choice buttons, and the typewriter effect.

```csharp
using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using TMPro;

public class DialogueUI : MonoBehaviour
{
    [Header("Panels")]
    [SerializeField] private GameObject dialoguePanel;
    [SerializeField] private GameObject choicePanel;

    [Header("Text Display")]
    [SerializeField] private TextMeshProUGUI speakerNameText;
    [SerializeField] private TextMeshProUGUI dialogueText;
    [SerializeField] private Image portraitImage;
    [SerializeField] private GameObject continueIndicator; // Blinking arrow

    [Header("Choice Buttons")]
    [SerializeField] private Transform choiceContainer;
    [SerializeField] private GameObject choiceButtonPrefab;

    [Header("Typewriter Settings")]
    [SerializeField] private float charactersPerSecond = 40f;
    [SerializeField] private AudioSource talkAudioSource;

    private Coroutine _typewriterCoroutine;
    private string _fullText;

    public bool IsTyping { get; private set; }

    public void Show()
    {
        dialoguePanel.SetActive(true);
        choicePanel.SetActive(false);
        continueIndicator.SetActive(false);
    }

    public void Hide()
    {
        dialoguePanel.SetActive(false);
        choicePanel.SetActive(false);
        if (_typewriterCoroutine != null)
            StopCoroutine(_typewriterCoroutine);
    }

    public void ShowText(string speakerName, string text, Sprite portrait)
    {
        choicePanel.SetActive(false);
        continueIndicator.SetActive(false);

        speakerNameText.text = speakerName;
        portraitImage.sprite = portrait;
        portraitImage.enabled = portrait != null;

        _fullText = text;
        if (_typewriterCoroutine != null)
            StopCoroutine(_typewriterCoroutine);
        _typewriterCoroutine = StartCoroutine(TypewriterEffect(text));
    }

    public void ShowChoices(List<DialogueChoice> choices, Action<int> onSelected)
    {
        choicePanel.SetActive(true);
        continueIndicator.SetActive(false);

        // Clear old buttons
        foreach (Transform child in choiceContainer)
            Destroy(child.gameObject);

        for (int i = 0; i < choices.Count; i++)
        {
            int index = i; // Capture for closure
            var choice = choices[i];

            var buttonGo = Instantiate(choiceButtonPrefab, choiceContainer);
            var buttonText = buttonGo.GetComponentInChildren<TextMeshProUGUI>();
            var button = buttonGo.GetComponent<Button>();

            buttonText.text = choice.choiceText;
            button.onClick.AddListener(() =>
            {
                choicePanel.SetActive(false);
                onSelected?.Invoke(index);
            });

            // Gray out unavailable choices
            if (!string.IsNullOrEmpty(choice.requiredConditionKey) &&
                !GameStateManager.Instance.CheckCondition(choice.requiredConditionKey))
            {
                button.interactable = false;
                buttonText.alpha = 0.5f;
            }
        }
    }

    public void CompleteTypewriter()
    {
        if (_typewriterCoroutine != null)
            StopCoroutine(_typewriterCoroutine);

        dialogueText.text = _fullText;
        IsTyping = false;
        continueIndicator.SetActive(true);
    }

    private IEnumerator TypewriterEffect(string text)
    {
        IsTyping = true;
        dialogueText.text = "";

        // Use TextMeshPro's maxVisibleCharacters for rich text support
        dialogueText.text = text;
        dialogueText.maxVisibleCharacters = 0;

        int totalChars = text.Length;
        float timer = 0f;

        for (int i = 0; i <= totalChars; i++)
        {
            dialogueText.maxVisibleCharacters = i;

            // Play talk blip sound (not every character, to avoid noise)
            if (i % 3 == 0 && talkAudioSource != null && talkAudioSource.clip != null)
            {
                talkAudioSource.pitch = UnityEngine.Random.Range(0.9f, 1.1f);
                talkAudioSource.PlayOneShot(talkAudioSource.clip);
            }

            yield return new WaitForSeconds(1f / charactersPerSecond);
        }

        IsTyping = false;
        continueIndicator.SetActive(true);
    }
}
```

---

## Typewriter Effect Details

The typewriter uses `TextMeshProUGUI.maxVisibleCharacters` instead of building the string character by character. This is important because it preserves rich text tags. If you build the string incrementally (`text = text.Substring(0, i)`), you will break tags like `<color=red>important</color>` mid-tag.

**Pause on punctuation:** Add brief pauses after periods, commas, and other punctuation for natural rhythm.

```csharp
private float GetCharacterDelay(char c)
{
    return c switch
    {
        '.' or '!' or '?' => 0.15f,
        ',' or ';' or ':' => 0.08f,
        _ => 1f / charactersPerSecond
    };
}
```

**Skip on input:** Let the player press the advance button to instantly show all text. The DialogueRunner handles this: if `IsTyping`, call `CompleteTypewriter()` instead of advancing to the next node.

---

## Localization-Ready Design

Never hardcode display text in nodes. Instead, use string keys that map to a localization table.

**Key format convention:** `dialogue.<conversation_id>.<node_id>`

Example:
- `dialogue.blacksmith_intro.001` = "Welcome to my forge, traveler."
- `dialogue.blacksmith_intro.002` = "What can I craft for you today?"
- `dialogue.blacksmith_intro.choice_buy` = "Show me your wares."
- `dialogue.blacksmith_intro.choice_leave` = "Maybe later."

During development, store the fallback text directly in the node so the game is playable without a localization system. When you add localization, the runner checks the key first and falls back to the raw text.

```csharp
private string GetLocalizedText(string locKey, string fallback)
{
    if (string.IsNullOrEmpty(locKey))
        return fallback;

    // Your localization system goes here.
    // Unity Localization package example:
    // var entry = LocalizationSettings.StringDatabase.GetTableEntry("Dialogue", locKey);
    // return entry?.Value ?? fallback;

    return fallback;
}
```

---

## Integration with Game State

Condition nodes check game state to branch dialogue. This enables NPCs to react differently based on quest progress, inventory contents, or player choices.

### Game State Manager (minimal interface)

```csharp
public class GameStateManager : MonoBehaviour
{
    public static GameStateManager Instance { get; private set; }

    private Dictionary<string, object> _state = new();

    private void Awake() => Instance = this;

    public void SetState(string key, object value) => _state[key] = value;

    public T GetState<T>(string key, T defaultValue = default)
    {
        if (_state.TryGetValue(key, out var value) && value is T typed)
            return typed;
        return defaultValue;
    }

    /// <summary>
    /// Check a condition key. Supports simple bool states
    /// and comparison expressions like "quest_forge >= 2".
    /// </summary>
    public bool CheckCondition(string conditionKey)
    {
        // Simple bool check
        if (_state.TryGetValue(conditionKey, out var value))
        {
            if (value is bool b) return b;
            if (value is int i) return i > 0;
            if (value is string s) return !string.IsNullOrEmpty(s);
        }

        return false;
    }
}
```

### Event Node Integration

Event nodes trigger side effects: give items, start quests, play animations, change affection, etc.

```csharp
public class GameEventManager : MonoBehaviour
{
    public static GameEventManager Instance { get; private set; }

    public event Action<string, string> OnGameEvent;

    private void Awake() => Instance = this;

    public void TriggerEvent(string eventName, string parameter)
    {
        Debug.Log($"[DialogueEvent] {eventName}: {parameter}");
        OnGameEvent?.Invoke(eventName, parameter);

        // Built-in handlers for common events
        switch (eventName)
        {
            case "set_state":
                // parameter format: "key=value"
                var parts = parameter.Split('=');
                if (parts.Length == 2)
                    GameStateManager.Instance.SetState(parts[0].Trim(), parts[1].Trim());
                break;

            case "give_item":
                // parameter format: "item_id:count"
                // Implement via your inventory system
                break;

            case "start_quest":
                // parameter: quest ID
                break;
        }
    }
}
```

---

## NPC Interaction Trigger

Attach to an NPC to start dialogue when the player interacts.

```csharp
using UnityEngine;

public class NPCDialogueTrigger : MonoBehaviour
{
    [SerializeField] private DialogueTree dialogue;
    [SerializeField] private DialogueTree[] conditionalDialogues;
    [SerializeField] private string[] conditionKeys;
    [SerializeField] private GameObject interactPrompt; // "Press E" UI

    private bool _playerInRange;

    /// <summary>
    /// Returns the first dialogue whose condition is met, or the default.
    /// </summary>
    private DialogueTree GetCurrentDialogue()
    {
        for (int i = 0; i < conditionalDialogues.Length; i++)
        {
            if (i < conditionKeys.Length &&
                GameStateManager.Instance.CheckCondition(conditionKeys[i]))
            {
                return conditionalDialogues[i];
            }
        }
        return dialogue;
    }

    // Called by InputView when the Interact action fires (see architecture rules — no Input.* here).
    public void OnInteractPressed()
    {
        if (!_playerInRange || DialogueRunner.Instance.IsRunning) return;
        interactPrompt.SetActive(false);
        DialogueRunner.Instance.StartDialogue(GetCurrentDialogue());
    }

    private void OnTriggerEnter2D(Collider2D other)
    {
        if (other.CompareTag("Player"))
        {
            _playerInRange = true;
            interactPrompt.SetActive(true);
        }
    }

    private void OnTriggerExit2D(Collider2D other)
    {
        if (other.CompareTag("Player"))
        {
            _playerInRange = false;
            interactPrompt.SetActive(false);
        }
    }
}
```

---

## Rich Text Support

TextMeshPro supports inline rich text tags. Use them for emphasis in dialogue:

- `<b>bold</b>` for important words
- `<color=#FF0000>red text</color>` for warnings or item names
- `<size=120%>large</size>` for shouting
- `<sprite name="coin">` for inline icons (requires TMP sprite asset)

The typewriter effect using `maxVisibleCharacters` handles these tags correctly because TMP processes the full string and only reveals characters progressively.

---

## Practical Tips

- **Auto-advance option:** Some players prefer dialogue to advance automatically after a delay. Add an accessibility toggle.
- **Log/history panel:** Store shown dialogue lines in a list so the player can review what was said. Useful for puzzle clues.
- **Editor tooling:** For large games, build a custom editor window (or use a tool like Yarn Spinner) for visual node editing. Editing node IDs and connections in the Inspector does not scale past a dozen conversations.
- **Voice acting support:** Add an `AudioClip` field to TextNode for voiced lines. Play the clip when the node is shown; auto-advance when the clip finishes.
- **Animated portraits:** Use an Animator component on the portrait image to play emotion animations (blink, talk, surprise) while text is typing.
- **Branching complexity:** Keep branches shallow (2-3 levels deep). Deep branching trees are hard to test and easy to break. Use condition nodes to converge branches back together.
