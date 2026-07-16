# C# Style — Unity Conventions

## Field Declarations

- `[SerializeField] private` for inspector-exposed fields — never public
- Private/protected fields use `_lowerCamelCase`: `_moveSpeed`, `_health`
- Public fields use `lowerCamelCase`: `moveSpeed`, `health`
- Properties (public and private) use `UpperCamelCase`: `MoveSpeed`, `Health`
- `static readonly` fields use `UpperCamelCase`: `JumpHash`, `DefaultColor`
- `const` fields use `UPPER_SNAKE_CASE`: `MAX_HEALTH`, `MAX_PLAYER_COUNT`
- `readonly` for fields set only in constructor or Awake

```csharp
[SerializeField] private float _moveSpeed = 5f;
[SerializeField] private Transform _spawnPoint;

private Rigidbody _rigidbody;
private static readonly int JumpHash = Animator.StringToHash("Jump");
private const int MAX_JUMP_COUNT = 3;
```

## Encapsulation (NON-NEGOTIABLE)

**Minimum visibility principle: everything is `private` unless proven otherwise.**

- Fields: `private` by default. Only use `[SerializeField] private` if the field MUST be configured in the Inspector. Do NOT add `[SerializeField]` speculatively — only when a designer/developer actually needs to tweak that value in the Inspector.
- Methods: `private` by default. Only make `public` if another class actually calls it. "Might be useful later" is NOT a reason.
- Properties: `private` by default. Expose a public getter only when another class reads it. Expose a public setter only when another class writes it.
- Classes/structs: `internal` by default when inside an assembly. Only `public` when consumed by other assemblies.
- Nested types: `private` unless external access is required.

**The test:** Before making anything non-private, identify the caller. If you can't name a concrete caller in the current codebase, it stays `private`. Agents must not generate speculative public API surface.

```csharp
// BAD — everything public "just in case"
public class EnemySystem
{
    public EnemyModel Model;                    // Should be private
    public void Initialize() { }                // Only called internally
    public int CalculateDamage() { return 5; }  // Only called internally
    public void TakeDamage(int amount) { }      // Actually called by CombatSystem — this one is fine
}

// GOOD — minimum viable visibility
public sealed class EnemySystem
{
    private readonly EnemyModel _model;
    
    private void Initialize() { }
    private int CalculateDamage() => 5;
    public void TakeDamage(int amount) { }  // CombatSystem calls this
}
```

**`[SerializeField]` discipline:**
```csharp
// BAD — serializing fields that don't need Inspector exposure
[SerializeField] private int _currentHealth;      // Runtime state, not config — don't serialize
[SerializeField] private bool _isInitialized;     // Internal flag — don't serialize
[SerializeField] private Transform _cachedTransform; // Cached ref — don't serialize

// GOOD — only serialize what designers configure
[SerializeField] private float _moveSpeed = 5f;   // Designer tweaks this in Inspector
[SerializeField] private GameObject _bulletPrefab; // Set via Inspector reference
private int _currentHealth;                         // Runtime state — plain private
private bool _isInitialized;                        // Internal flag — plain private
```

## Types and Naming

- Use `var` when the type is obvious from the right-hand side. Use explicit types when it isn't
- One type per file — file name MUST match the primary class/struct name (Unity requirement for MonoBehaviour)
- `sealed` by default — only unseal when inheritance is explicitly designed
- Explicit access modifiers on everything — no implicit `private`

## Structure Ordering

```csharp
public sealed class PlayerController : MonoBehaviour
{
    // 1. Serialized fields
    // 2. Private fields / cached references
    // 3. Properties
    // 4. Unity lifecycle: Awake, OnEnable, Start, FixedUpdate, Update, LateUpdate, OnDisable, OnDestroy
    // 5. Public methods
    // 6. Private methods
}
```

## Control Flow

- Braces always, even for single-line `if`/`for`/`while`
- `for` over `foreach` in hot paths (Update, FixedUpdate)
- No abbreviated loop variables — `for (int enemyIndex = 0; ...)` not `for (int i = 0; ...)`
- No magic strings — use `nameof()`, `Animator.StringToHash()`, `Shader.PropertyToID()`

## Other

- No LINQ in gameplay code
- `StringBuilder` for string building
- `CompareTag("tag")` not `tag == "tag"`
