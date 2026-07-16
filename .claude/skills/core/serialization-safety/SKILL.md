---
name: serialization-safety
description: "Unity serialization rules — FormerlySerializedAs on renames, SerializeField vs public, SerializeReference for polymorphism, Unity null check (== null not ?.). CRITICAL: prevents silent data loss."
alwaysApply: true
---

# Serialization Safety

This is the single most important skill. Serialization mistakes cause **silent data loss** — every configured value in every scene, prefab, and ScriptableObject resets to default with zero warning.

## Rule 1: FormerlySerializedAs on ANY Rename

```csharp
// BEFORE: field is called _speed
[SerializeField] private float _speed = 5f;

// AFTER: renaming to _moveSpeed — MUST add FormerlySerializedAs
[FormerlySerializedAs("_speed")]
[SerializeField] private float _moveSpeed = 5f;
```

**Why:** Unity serializes fields by name. Renaming breaks the name → value mapping. Every scene, prefab, and SO that configured this field silently loses its value. `[FormerlySerializedAs]` tells Unity "this field used to be called X."

The attribute stays **forever**. Never remove it.

## Rule 2: Unity Null Check

```csharp
// CORRECT — Unity overrides == to detect destroyed objects
if (_target == null) return;
if (_target != null) _target.TakeDamage(10);

// WRONG — bypasses Unity's destroyed-object detection
if (_target is null) return;        // C# null check, misses destroyed
_target?.TakeDamage(10);            // ?. bypasses Unity ==, calls on destroyed
_target ??= FindNewTarget();        // ??= uses C# null, not Unity null
```

**Why:** Unity objects can be "destroyed" (C++ side freed) but not yet garbage collected (C# reference still exists). Unity overrides `==` to return `true` for destroyed objects. C# pattern matching (`is null`, `?.`, `??`) uses reference equality, which returns `false` — so you call methods on destroyed objects, causing crashes or undefined behavior.

## Rule 3: What Unity Serializes

**Serialized:**
- `public` fields (without `[NonSerialized]`)
- `[SerializeField] private/protected` fields
- Types: `int`, `float`, `bool`, `string`, `Vector2/3/4`, `Color`, `Rect`, `Quaternion`, `AnimationCurve`, `Gradient`, enums, `UnityEngine.Object` subclasses, arrays, `List<T>`, `[Serializable]` structs/classes

**NOT Serialized:**
- Properties (getters/setters) — even with `[SerializeField]`
- `static` fields
- `readonly` fields
- `const` fields
- `Dictionary<K,V>` — use `ISerializationCallbackReceiver`
- Interfaces / abstract types — use `[SerializeReference]`
- Delegates / events

## Rule 4: SerializeField Private Over Public

```csharp
// GOOD — controlled exposure
[SerializeField] private float _health = 100f;
public float Health => _health; // Read-only access

// BAD — anyone can modify, clutters API
public float health = 100f;
```

## Rule 5: SerializeReference for Polymorphism

```csharp
// Without SerializeReference: Unity serializes as base type, losing derived data
[SerializeField] private IAbility _ability; // ERROR: interfaces not serialized

// With SerializeReference: polymorphic serialization
[SerializeReference] private IAbility _ability; // Works: stores concrete type
```

## Rule 6: NonSerialized for Cached Data

```csharp
public class Enemy : MonoBehaviour
{
    [SerializeField] private float _maxHealth = 100f;

    [NonSerialized] public float CurrentHealth; // Runtime-only, not saved
    
    private Transform _cachedTransform; // Private non-serialized by default (good)
}
```

## Rule 7: ISerializationCallbackReceiver for Dictionaries

```csharp
public class DataStore : MonoBehaviour, ISerializationCallbackReceiver
{
    // Unity serializes these lists
    [SerializeField] private List<string> _keys = new();
    [SerializeField] private List<float> _values = new();

    // Runtime dictionary (not serialized directly)
    private Dictionary<string, float> _data = new();

    public void OnBeforeSerialize()
    {
        _keys.Clear();
        _values.Clear();
        foreach (KeyValuePair<string, float> pair in _data)
        {
            _keys.Add(pair.Key);
            _values.Add(pair.Value);
        }
    }

    public void OnAfterDeserialize()
    {
        _data = new Dictionary<string, float>();
        for (int i = 0; i < _keys.Count; i++)
        {
            _data[_keys[i]] = _values[i];
        }
    }
}
```

## Rule 8: Serialization Depth Limit

Unity stops serializing at **7 levels** of nesting. Deeply nested data structures are silently truncated. If you need deep data, flatten it or use `[SerializeReference]`.

## Rule 9: HideInInspector vs NonSerialized

- `[HideInInspector]` — hides from Inspector but **still serializes** (data is saved)
- `[NonSerialized]` — prevents serialization entirely (data is not saved, resets on play)

## Rule 10: Auto-Property Serialization

```csharp
// C# 7.3+ syntax for serialized auto-properties
[field: SerializeField] public float Speed { get; private set; }

// Note: FormerlySerializedAs uses the backing field name:
[field: FormerlySerializedAs("<Speed>k__BackingField")]
[field: SerializeField] public float MoveSpeed { get; private set; }
```
