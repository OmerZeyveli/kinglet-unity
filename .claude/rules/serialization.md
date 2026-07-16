# Serialization Rules

## CRITICAL: FormerlySerializedAs

When renaming ANY serialized field, you MUST add `[FormerlySerializedAs]`:

```csharp
// Renaming _speed to _moveSpeed:
[FormerlySerializedAs("_speed")]
[SerializeField] private float _moveSpeed;
```

**Why:** Without this, Unity cannot map the old serialized data to the new field name. Every configured value in every scene, prefab, and ScriptableObject silently resets to default. Hours of artist/designer work lost with zero warning.

The `[FormerlySerializedAs]` attribute stays forever. Never remove it.

## What Unity Serializes

**Serialized:**
- `public` fields (without `[NonSerialized]`)
- `[SerializeField] private` fields
- Supported types: primitives, string, Vector2/3/4, Color, Rect, AnimationCurve, enums, arrays, List<T>, UnityEngine.Object references

**NOT Serialized:**
- Properties (even with `[SerializeField]`)
- `static` fields
- `readonly` fields
- `const` fields
- `Dictionary<K,V>` (use `ISerializationCallbackReceiver`)
- Interfaces/abstract types (use `[SerializeReference]`)

## Field Exposure

```csharp
// GOOD — private with explicit serialization
[SerializeField] private float _health = 100f;

// BAD — public exposes to inspector AND code
public float health = 100f;  // (note: if public is needed, use lowerCamelCase)

// For auto-properties (C# 7.3+):
[field: SerializeField] public float Health { get; private set; }
```

- `[HideInInspector]` — hides from inspector but STILL serializes
- `[NonSerialized]` — prevents serialization entirely (for cached/computed data on public fields)

## Unity Null Check

```csharp
// CORRECT — Unity overrides == to detect destroyed objects
if (_target == null) return;

// WRONG — bypasses Unity's destroyed-object detection
if (_target is null) return;      // C# null check, misses destroyed
if (_target?.Method() != null)    // ?. bypasses Unity's ==, calls method on destroyed object
```

Unity objects can be "destroyed" but not garbage collected. `== null` returns true for destroyed objects. `?.` and `is null` use C# reference equality, which returns false — leading to calls on destroyed objects.

## Polymorphic Serialization

```csharp
// For interface/abstract fields:
[SerializeReference] private IAbility _ability;
```

Without `[SerializeReference]`, Unity serializes by value and loses type information.

## Custom Types

```csharp
// Dictionary serialization via callback:
public class MyData : MonoBehaviour, ISerializationCallbackReceiver
{
    [SerializeField] private List<string> _keys = new();
    [SerializeField] private List<int> _values = new();

    private Dictionary<string, int> _lookup = new();

    public void OnBeforeSerialize()
    {
        _keys.Clear();
        _values.Clear();
        foreach (KeyValuePair<string, int> pair in _lookup)
        {
            _keys.Add(pair.Key);
            _values.Add(pair.Value);
        }
    }

    public void OnAfterDeserialize()
    {
        _lookup.Clear();
        for (int i = 0; i < _keys.Count; i++)
        {
            _lookup[_keys[i]] = _values[i];
        }
    }
}
```

## Depth Limit

Unity serialization stops at 7 levels of nesting. Deeply nested data structures will be silently truncated.

## Prefab Overrides

Changing a serialized field on a prefab instance creates a prefab override. `[FormerlySerializedAs]` preserves these overrides during renames. Without it, all overrides are lost.
