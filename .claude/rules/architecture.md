# Architecture Rules

## Model-View-System (MVS) Pattern

All features follow a strict three-layer separation:

```
Model  — Pure C# classes. State + data only. No Unity API, no MonoBehaviour.
View   — MonoBehaviour. Reads Model, renders visuals, forwards input. No logic.
System — Plain C# class (registered in VContainer). Owns and mutates Models. Contains all logic.
```

```csharp
// --- Model (pure C#, serializable, no Unity dependencies) ---
public sealed class PlayerModel
{
    public ReactiveProperty<int> Health { get; } = new(100);
    public ReactiveProperty<Vector3> Position { get; } = new(Vector3.zero);
    public bool IsDead => Health.Value <= 0;
}

// --- System (plain C#, injected via VContainer, owns the Model) ---
public sealed class PlayerSystem : IDisposable
{
    private readonly PlayerModel _model;
    private readonly IPublisher<PlayerDiedMessage> _diedPublisher;

    [Inject]
    public PlayerSystem(PlayerModel model, IPublisher<PlayerDiedMessage> diedPublisher)
    {
        _model = model;
        _diedPublisher = diedPublisher;
    }

    public void TakeDamage(int amount)
    {
        _model.Health.Value = Mathf.Max(0, _model.Health.Value - amount);
        if (_model.IsDead)
        {
            _diedPublisher.Publish(new PlayerDiedMessage());
        }
    }

    public void Dispose() { }
}

// --- View (MonoBehaviour, observes Model, no logic) ---
public sealed class PlayerView : MonoBehaviour
{
    [SerializeField] private Slider _healthBar;

    private PlayerModel _model;
    private readonly CompositeDisposable _disposables = new();

    [Inject]
    public void Construct(PlayerModel model)
    {
        _model = model;
    }

    private void Start()
    {
        _model.Health
            .Subscribe(hp => _healthBar.value = hp / 100f)
            .AddTo(_disposables);
    }

    private void OnDestroy() => _disposables.Dispose();
}
```

**Rules:**
- Models NEVER reference Views or Systems
- Systems NEVER reference Views
- Views observe Models via `ReactiveProperty<T>.Subscribe()` — no polling in Update
- Views call Systems for actions (injected via VContainer)
- One System can own multiple Models; one View binds to one primary Model

## VContainer for Dependency Injection

VContainer is the **only** way to wire dependencies. No singletons, no static access, no `FindObjectOfType`.

### NO GameContext / Service Locator (NON-NEGOTIABLE)

Do NOT create a `GameContext`, `ServiceLocator`, `Dependencies`, or any "god container" class that bundles multiple dependencies into a single injectable object. This is a **Service Locator anti-pattern** that defeats the purpose of DI.

```csharp
// BAD — GameContext exposes everything to everyone
public class GameContext
{
    public PlayerModel Player { get; }
    public ScoreSystem Score { get; }      // Why should SpawnView see this?
    public SpawnSystem Spawner { get; }    // Why should ScoreView see this?
    public IAudioService Audio { get; }
}

// Every consumer gets access to ALL dependencies
public sealed class ScoreView : MonoBehaviour
{
    [Inject]
    public void Construct(GameContext ctx)  // Real dependencies are hidden
    {
        _score = ctx.Score;  // Could also access ctx.Spawner — no access control
    }
}
```

**Why this is wrong:**
- **Violates least-privilege**: every consumer can access every dependency
- **Hides real dependencies**: the constructor/Construct signature says "I need GameContext" instead of "I need ScoreModel"
- **Untestable**: testing one class requires constructing the entire GameContext with all its dependencies
- **Binding ≠ injection**: GameContext construction becomes a second wiring step outside the LifetimeScope, duplicating responsibility
- **Properties that should be private are exposed**: GameContext forces public access on dependencies that only specific consumers need

```csharp
// GOOD — each class declares exactly what it needs
public sealed class ScoreView : MonoBehaviour
{
    private ScoreModel _model;

    [Inject]
    public void Construct(ScoreModel model)  // Only what it needs — nothing else visible
    {
        _model = model;
    }
}

public sealed class CombatSystem : IDisposable
{
    private readonly PlayerModel _player;
    private readonly IPublisher<DamageDealtMessage> _pub;

    // Constructor declares exact dependencies — self-documenting, testable
    public CombatSystem(PlayerModel player, IPublisher<DamageDealtMessage> pub)
    {
        _player = player;
        _pub = pub;
    }
}
```

**The rule:** Every class requests only its own dependencies via constructor (Systems) or `[Inject] Construct` (Views). The LifetimeScope is the single place where binding and resolution happens. No intermediary container objects.

```csharp
public sealed class GameLifetimeScope : LifetimeScope
{
    protected override void Configure(IContainerBuilder builder)
    {
        // Models — singleton per scope
        builder.Register<PlayerModel>(Lifetime.Singleton);
        builder.Register<InventoryModel>(Lifetime.Singleton);

        // Systems — singleton per scope
        builder.Register<PlayerSystem>(Lifetime.Singleton).AsImplementedInterfaces().AsSelf();
        builder.Register<InventorySystem>(Lifetime.Singleton).AsImplementedInterfaces().AsSelf();

        // Services — interface-based for swappability
        builder.Register<SaveService>(Lifetime.Singleton).As<ISaveService>();

        // Views — use EntryPoint for non-MonoBehaviour tick
        builder.RegisterEntryPoint<GameLoopSystem>();

        // MonoBehaviour views — find in scene or prefab
        builder.RegisterComponentInHierarchy<PlayerView>();

        // MessagePipe
        var messagePipeOptions = builder.RegisterMessagePipe();
        builder.RegisterMessageBroker<PlayerDiedMessage>(messagePipeOptions);
        builder.RegisterMessageBroker<ScoreChangedMessage>(messagePipeOptions);
        builder.RegisterMessageBroker<ItemPickedUpMessage>(messagePipeOptions);
    }
}
```

**Scope hierarchy:**
```
RootLifetimeScope          — app-wide services (audio, save, settings)
  └─ SceneLifetimeScope    — per-scene systems and models
       └─ Child scopes     — per-feature (e.g., UI popup, spawned entity)
```

- Use `Lifetime.Singleton` for shared state within a scope
- Use `Lifetime.Transient` for stateless services or factories
- Use child scopes for dynamically spawned entities that need injection
- NEVER use `[Inject]` on fields — use constructor injection for Systems, method injection (`[Inject] public void Construct(...)`) for MonoBehaviours

## MessagePipe for Communication

MessagePipe is the **only** messaging system. No SO event channels, no static EventBus, no C# events for cross-system communication.

```csharp
// --- Define messages as readonly structs ---
public readonly struct PlayerDiedMessage { }

public readonly struct DamageDealtMessage
{
    public readonly int Amount;
    public readonly Vector3 Position;

    public DamageDealtMessage(int amount, Vector3 position)
    {
        Amount = amount;
        Position = position;
    }
}

// --- Publishing (System → System or System → View) ---
public sealed class CombatSystem : IDisposable
{
    private readonly IPublisher<DamageDealtMessage> _damagePublisher;

    [Inject]
    public CombatSystem(IPublisher<DamageDealtMessage> damagePublisher)
    {
        _damagePublisher = damagePublisher;
    }

    public void DealDamage(int amount, Vector3 position)
    {
        _damagePublisher.Publish(new DamageDealtMessage(amount, position));
    }

    public void Dispose() { }
}

// --- Subscribing (in System or View) ---
public sealed class DamagePopupSystem : IDisposable
{
    private readonly IDisposable _subscription;

    [Inject]
    public DamagePopupSystem(ISubscriber<DamageDealtMessage> damageSubscriber)
    {
        _subscription = damageSubscriber.Subscribe(OnDamageDealt);
    }

    private void OnDamageDealt(DamageDealtMessage message)
    {
        // spawn popup at message.Position showing message.Amount
    }

    public void Dispose() => _subscription.Dispose();
}
```

**Rules:**
- Messages are `readonly struct` — zero allocation
- Register all message brokers in the LifetimeScope
- Always dispose subscriptions (Systems via `IDisposable`, Views via `CompositeDisposable`)
- Use `IAsyncSubscriber<T>` with UniTask when the handler needs async work
- Use `IBufferedPublisher<T>` / `IBufferedSubscriber<T>` when late subscribers need the last value

## UniTask for Async

UniTask replaces coroutines entirely. No `StartCoroutine`, no `IEnumerator`, no `yield return`.

```csharp
public sealed class WaveSpawnerSystem : IDisposable
{
    private readonly CancellationTokenSource _cts = new();

    public async UniTaskVoid StartSpawning()
    {
        for (int waveIndex = 0; waveIndex < 10; waveIndex++)
        {
            await SpawnWave(waveIndex, _cts.Token);
            await UniTask.Delay(TimeSpan.FromSeconds(5), cancellationToken: _cts.Token);
        }
    }

    private async UniTask SpawnWave(int waveIndex, CancellationToken token)
    {
        int enemyCount = waveIndex * 3;
        for (int enemyIndex = 0; enemyIndex < enemyCount; enemyIndex++)
        {
            // spawn logic
            await UniTask.Delay(TimeSpan.FromSeconds(0.2f), cancellationToken: token);
        }
    }

    public void Dispose() => _cts.Cancel();
}
```

**Rules:**
- Always pass `CancellationToken` — typically from `this.GetCancellationTokenOnDestroy()` in Views, or a `CancellationTokenSource` in Systems
- Use `UniTask` for awaitable operations, `UniTaskVoid` for fire-and-forget
- Use `UniTask.Delay` instead of `new WaitForSeconds`
- Use `UniTask.WhenAll` for parallel async operations
- Use `UniTask.SwitchToMainThread()` when returning from background thread
- No `async void` — always `async UniTask` or `async UniTaskVoid`

## Composition Over Inheritance

MonoBehaviour is a component, not a base class. Don't build deep inheritance trees.

Max MonoBehaviour inheritance depth: 2 (base + one subclass). Beyond that, compose.

Views should be thin — the logic lives in Systems, data lives in Models.

## ScriptableObjects for Static Data

Items, abilities, enemy configs, level data — all should be ScriptableObjects:

```csharp
[CreateAssetMenu(menuName = "Game/Weapon Definition")]
public sealed class WeaponDefinition : ScriptableObject
{
    [SerializeField] private string _displayName;
    [SerializeField] private float _damage;
    [SerializeField] private float _fireRate;
    [SerializeField] private GameObject _prefab;
}
```

ScriptableObjects hold **static/config data**. Runtime mutable state goes in Models.

## Input System Architecture (NON-NEGOTIABLE)

Input is a **View-layer concern**. It follows the same MVS pattern: InputView reads raw input and forwards it to Systems. Systems never touch Unity Input directly.

### InputView Pattern

```csharp
// InputView — thin adapter between New Input System and game Systems
public sealed class InputView : MonoBehaviour
{
    private PlayerControls _controls;
    private PlayerSystem _playerSystem;
    private UISystem _uiSystem;

    private void Awake()
    {
        _controls = new PlayerControls();
    }

    [Inject]
    public void Construct(PlayerSystem playerSystem, UISystem uiSystem)
    {
        _playerSystem = playerSystem;
        _uiSystem = uiSystem;
    }

    private void OnEnable()
    {
        _controls.Player.Enable();
        _controls.Player.Jump.performed += OnJump;
        _controls.Player.Attack.performed += OnAttack;
        _controls.Player.Pause.performed += OnPause;
    }

    private void OnDisable()
    {
        _controls.Player.Jump.performed -= OnJump;
        _controls.Player.Attack.performed -= OnAttack;
        _controls.Player.Pause.performed -= OnPause;
        _controls.Player.Disable();
    }

    private void Update()
    {
        Vector2 move = _controls.Player.Move.ReadValue<Vector2>();
        _playerSystem.SetMoveInput(move);
    }

    private void OnJump(InputAction.CallbackContext ctx) => _playerSystem.Jump();
    private void OnAttack(InputAction.CallbackContext ctx) => _playerSystem.Attack();
    private void OnPause(InputAction.CallbackContext ctx) => _uiSystem.TogglePause();
}
```

### VContainer Registration

```csharp
protected override void Configure(IContainerBuilder builder)
{
    // InputView is a MonoBehaviour — find in scene
    builder.RegisterComponentInHierarchy<InputView>();
}
```

### Rules
- **InputView owns PlayerControls** — no other class creates or holds a `PlayerControls` instance
- **InputView is a View** — it reads input and calls Systems. Zero game logic
- **Systems are input-agnostic** — they expose methods like `SetMoveInput(Vector2)`, `Jump()`, `Attack()`. They never know where input comes from (keyboard, gamepad, AI, network replay)
- **One InputView per scene** — prevents duplicate action subscriptions
- **Enable/Disable is mandatory** — `OnEnable` enables action maps, `OnDisable` disables them and unsubscribes callbacks
- **Continuous input in Update** — read `ReadValue<Vector2>()` in Update, cache it. Apply physics in FixedUpdate using cached values
- **Discrete input via callbacks** — button presses use `performed` callbacks, not polling
- **Action map switching lives in InputView** — controlled by Systems via method calls (e.g., `SwitchToUI()`, `SwitchToGameplay()`)

### Testing Input-Driven Systems

Because Systems are input-agnostic, they are trivially testable:
```csharp
[Test]
public void SetMoveInput_WithRightVector_UpdatesModelPosition()
{
    var model = new PlayerModel();
    var sut = new PlayerSystem(model);

    sut.SetMoveInput(Vector2.right);
    sut.Tick(1f);

    Assert.That(model.Position.Value.x, Is.GreaterThan(0));
}
```

No input mocking needed — the System never sees InputAction, PlayerControls, or any Unity Input type.

## Dependency Direction

```
Views → Systems → Models
  ↓        ↓
MessagePipe (decoupled communication)
```

- Views depend on Systems and Models (via VContainer injection)
- Systems depend on Models and other Systems (via VContainer injection)
- Models depend on nothing
- Cross-system communication goes through MessagePipe, never direct references
- Assembly definitions enforce direction at compile time

## No God Objects

```csharp
// BAD
class GameManager : MonoBehaviour
{
    // Handles: score, lives, spawning, UI, audio, saving, input, pause...
}

// GOOD — separate Systems registered in VContainer
// PlayerSystem — health, movement
// ScoreSystem — scoring, combos
// SpawnSystem — enemy waves
// Each is a plain C# class with injected dependencies
```

## Scene Independence

Each scene should be loadable independently via LifetimeScope hierarchy:
1. `RootLifetimeScope` lives in a bootstrap scene (app-wide services, DontDestroyOnLoad)
2. Each game scene has its own `SceneLifetimeScope` that inherits from Root
3. No hidden dependencies on "the scene before this one"
4. Scene loading/unloading is async via UniTask:

```csharp
await SceneManager.LoadSceneAsync("GameScene", LoadSceneMode.Additive).ToUniTask();
```

## No Singletons

VContainer replaces all singleton patterns. Register as `Lifetime.Singleton` in the appropriate scope instead.

- Need app-wide? Register in `RootLifetimeScope`
- Need per-scene? Register in `SceneLifetimeScope`
- Need per-feature? Create a child scope
