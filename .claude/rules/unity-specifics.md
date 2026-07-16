# Unity-Specific Rules

## Editor vs Runtime

```csharp
// Runtime code (Assets/Scripts/) — NEVER use UnityEditor unguarded
#if UNITY_EDITOR
using UnityEditor;
#endif

private void OnValidate()
{
    #if UNITY_EDITOR
    EditorUtility.SetDirty(this);
    #endif
}
```

- Code in `Editor/` folder: editor-only, excluded from builds automatically
- Code outside `Editor/`: must guard any `UnityEditor` usage with `#if UNITY_EDITOR`
- Forgetting the guard: compiles in Editor, **fails on build** with no warning until build time

## Platform Defines

```csharp
// GOOD — always provide fallback
#if UNITY_ANDROID
    string dataPath = Application.persistentDataPath;
#elif UNITY_IOS
    string dataPath = Application.persistentDataPath;
#else
    string dataPath = Application.dataPath;
#endif

// BAD — code silently excluded on other platforms
#if UNITY_ANDROID
    SetupMobileControls();
#endif
```

## The `?.` Operator Trap

```csharp
// DANGEROUS — bypasses Unity's destroyed-object detection
_target?.TakeDamage(10);  // Calls TakeDamage on destroyed objects!

// SAFE — Unity's == operator detects destroyed objects
if (_target != null)
{
    _target.TakeDamage(10);
}
```

Unity overrides `==` to return `true` when comparing destroyed objects to `null`. The `?.` operator uses C# reference equality, which does NOT detect destroyed objects. This is the #1 most subtle Unity bug.

## Lifecycle Order

```
Awake()       → called once when object is created (even if disabled)
OnEnable()    → called when object becomes active
Start()       → called once before first Update (only if enabled)
FixedUpdate() → physics tick (0.02s default)
Update()      → every frame
LateUpdate()  → every frame, after all Updates
OnDisable()   → called when object becomes inactive
OnDestroy()   → called when object is destroyed
```

- Don't depend on Awake order across objects — use `[DefaultExecutionOrder]` or explicit init
- `OnDisable` is called before `OnDestroy` — unsubscribe events in `OnDisable`
- `Start` is NOT called if the object is never enabled

## Threading

Unity API is main-thread only. Background threads cannot:
- Access `Transform`, `GameObject`, `Component`
- Call `Instantiate`, `Destroy`
- Access `Time`, `Input`, `Physics`

```csharp
// Return to main thread with UniTask:
await UniTask.SwitchToMainThread();

// Or with SynchronizationContext:
SynchronizationContext.Current.Post(_ => { /* Unity API here */ }, null);
```

## No Coroutines — Use UniTask

Do not use `StartCoroutine` / `IEnumerator` / `yield return`. Use UniTask for all async work.

Coroutine problems that UniTask solves:
- Coroutines stop silently when `gameObject.SetActive(false)` and don't resume
- Coroutines have no cancellation, error handling, or return values
- Coroutines allocate on the heap

```csharp
// BAD — coroutine
private IEnumerator WaitAndDo()
{
    yield return new WaitForSeconds(1f);
    DoSomething();
}

// GOOD — UniTask
private async UniTask WaitAndDoAsync(CancellationToken token)
{
    await UniTask.Delay(TimeSpan.FromSeconds(1), cancellationToken: token);
    DoSomething();
}
```

Always pass `CancellationToken`. In Views: `this.GetCancellationTokenOnDestroy()`. In Systems: own a `CancellationTokenSource` and cancel in `Dispose()`.

## DontDestroyOnLoad

Use sparingly. Prefer a bootstrapper scene pattern:
```
BootstrapScene (loads once, contains persistent services)
    → Additively loads GameScene, MenuScene, etc.
```

## Transform

- `transform.SetParent(parent, false)` — use `worldPositionStays: false` to preserve local transform
- `Application.isPlaying` — check in OnDisable/OnDestroy to avoid cleanup during editor domain reload

## Time

- `Time.deltaTime` in `Update` and `LateUpdate`
- `Time.fixedDeltaTime` in `FixedUpdate`
- Never use `Time.deltaTime` in `FixedUpdate` (it equals `fixedDeltaTime` there, but it's confusing)
- `Time.unscaledDeltaTime` for pause-independent logic (UI animations, etc.)

## Component Attributes

```csharp
[RequireComponent(typeof(Rigidbody))]        // Auto-adds Rigidbody, prevents removal
[DisallowMultipleComponent]                   // Prevents duplicate components
[DefaultExecutionOrder(-100)]                 // Runs before default scripts
[SelectionBase]                               // Click selects this object, not children
```

## Input System (NON-NEGOTIABLE)

The New Input System package is **mandatory**. Legacy `Input.GetKey`/`Input.GetAxis` is **BLOCKED** by hooks.

### Generated C# Class (Preferred Approach)

1. Create `Assets/Input/PlayerControls.inputactions` — define all action maps
2. Enable "Generate C# Class" in the asset inspector → generates `PlayerControls.cs`
3. Use the generated class in InputView (see architecture rules)

### Critical Lifecycle Rules

```csharp
// InputView — the ONLY place that touches PlayerControls
public sealed class InputView : MonoBehaviour
{
    private PlayerControls _controls;
    private PlayerSystem _playerSystem;

    private void Awake()
    {
        _controls = new PlayerControls();
    }

    [Inject]
    public void Construct(PlayerSystem playerSystem)
    {
        _playerSystem = playerSystem;
    }

    // MANDATORY: Enable actions in OnEnable
    private void OnEnable()
    {
        _controls.Player.Enable();
        _controls.Player.Jump.performed += OnJump;
        _controls.Player.Attack.performed += OnAttack;
    }

    // MANDATORY: Disable actions and unsubscribe in OnDisable
    private void OnDisable()
    {
        _controls.Player.Jump.performed -= OnJump;
        _controls.Player.Attack.performed -= OnAttack;
        _controls.Player.Disable();
    }

    // Read continuous input in Update, cache for systems
    private void Update()
    {
        Vector2 moveInput = _controls.Player.Move.ReadValue<Vector2>();
        _playerSystem.SetMoveInput(moveInput);
    }

    private void OnJump(InputAction.CallbackContext ctx) => _playerSystem.Jump();
    private void OnAttack(InputAction.CallbackContext ctx) => _playerSystem.Attack();
}
```

### Rules

| Rule | Why |
|------|-----|
| **Enable in OnEnable, Disable in OnDisable** | Missing Enable = zero input received. Missing Disable = ghost callbacks, leaks |
| **Subscribe in OnEnable, unsubscribe in OnDisable** | Every `+=` must have a matching `-=` in OnDisable |
| **Read continuous input in Update** | FixedUpdate runs at different rate — input can be missed |
| **Cache input, apply in FixedUpdate** | Physics forces use cached values, not raw reads |
| **Never use legacy Input API** | `Input.GetKey`, `Input.GetAxis`, `Input.GetButton` are BLOCKED |
| **InputView is a View** | Pure thin adapter — reads input, calls Systems. Zero logic |
| **One InputView per scene** | Centralized input reading prevents duplicate subscriptions |

### Action Map Switching

```csharp
// Gameplay → UI (e.g., opening pause menu)
_controls.Player.Disable();
_controls.UI.Enable();

// UI → Gameplay (closing menu)
_controls.UI.Disable();
_controls.Player.Enable();
```

Always disable the current map **before** enabling the next. Never leave multiple gameplay maps enabled simultaneously.

## .meta Files

- NEVER edit manually
- ALWAYS commit alongside their asset
- Missing .meta = Unity regenerates GUID = all references break
- Orphaned .meta = clutter and potential conflicts
