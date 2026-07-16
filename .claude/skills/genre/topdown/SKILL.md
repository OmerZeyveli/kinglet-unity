---
name: topdown
description: "Top-down game architecture — twin-stick gamepad and WASD + mouse-aim movement, click-to-move, room transitions, fog of war, spawner patterns, wave systems, minimap."
globs: ["**/TopDown*.cs", "**/Room*.cs", "**/Wave*.cs", "**/Spawn*.cs"]
---

# Top-Down Game Patterns

## Movement Types

Movement and aim are separate concerns in a top-down game. Bind both through the New Input System so
gamepad and keyboard+mouse are the same code path — only the aim source differs.

### Twin-Stick (Gamepad — primary)
```csharp
public sealed class TwinStickController : MonoBehaviour
{
    [SerializeField] private float _moveSpeed = 6f;
    [SerializeField] private float _stickDeadZone = 0.1f;

    private Rigidbody2D _rb;
    private Vector2 _moveInput;
    private Vector2 _aimInput;

    private void Awake()
    {
        _rb = GetComponent<Rigidbody2D>();
    }

    /// <summary>
    /// Bound to the "Move" action — left stick / WASD
    /// </summary>
    public void OnMove(InputAction.CallbackContext context)
    {
        Vector2 input = context.ReadValue<Vector2>();
        _moveInput = input.magnitude > _stickDeadZone ? input : Vector2.zero;
    }

    /// <summary>
    /// Bound to the "Aim" action — right stick (auto-fire while aiming)
    /// </summary>
    public void OnAim(InputAction.CallbackContext context)
    {
        Vector2 input = context.ReadValue<Vector2>();
        if (input.magnitude > _stickDeadZone)
        {
            _aimInput = input;
        }
    }

    private void FixedUpdate()
    {
        _rb.linearVelocity = _moveInput.normalized * _moveSpeed;

        // Aim with the right stick; fall back to facing the move direction
        Vector2 facing = _aimInput.sqrMagnitude > 0.01f ? _aimInput : _moveInput;
        if (facing.sqrMagnitude > 0.01f)
        {
            float angle = Mathf.Atan2(facing.y, facing.x) * Mathf.Rad2Deg - 90f;
            transform.rotation = Quaternion.Euler(0f, 0f, angle);
        }
    }
}
```

### Mouse Aim (Keyboard + Mouse)
```csharp
// Movement reuses the same "Move" action (WASD). Only the aim source changes:
// instead of the right stick, face the cursor's world position.
private void AimAtCursor()
{
    if (Mouse.current == null) return;

    Vector2 screenPos = Mouse.current.position.ReadValue();
    Vector3 worldPos = _camera.ScreenToWorldPoint(screenPos);
    Vector2 toCursor = (Vector2)worldPos - _rb.position;

    if (toCursor.sqrMagnitude > 0.01f)
    {
        float angle = Mathf.Atan2(toCursor.y, toCursor.x) * Mathf.Rad2Deg - 90f;
        transform.rotation = Quaternion.Euler(0f, 0f, angle);
    }
}
```

Common in twin-stick PC/console shooters (Hades, Enter the Gungeon, Nuclear Throne).

Track the last-used device and swap aim modes on the fly — a player on keyboard+mouse who picks up a
gamepad should not have to open a menu. Use `InputUser.onChange` or the `PlayerInput` control-scheme
callbacks; never hard-assume one device is connected.

### Click-to-Move (NavMeshAgent)
```csharp
private NavMeshAgent _agent;
private Camera _camera;

private void Update()
{
    if (Mouse.current == null) return;

    if (Mouse.current.rightButton.wasPressedThisFrame)
    {
        Vector2 screenPos = Mouse.current.position.ReadValue();
        Ray ray = _camera.ScreenPointToRay(screenPos);
        if (Physics.Raycast(ray, out RaycastHit hit, 100f, _groundLayer))
        {
            _agent.SetDestination(hit.point);
        }
    }
}
```

On gamepad, drive the agent from the left stick directly (`_agent.Move`) rather than synthesizing a
cursor — click-to-move is a mouse idiom and rarely worth emulating with a stick.

## Camera Setup

- Orthographic camera, fixed Y height
- Cinemachine with Framing Transposer (damping for smooth follow)
- Confiner 2D for room bounds (PolygonCollider2D)

## Room Transitions

```csharp
public sealed class RoomTransition : MonoBehaviour
{
    [SerializeField] private Transform _spawnPoint;
    [SerializeField] private CinemachineConfiner2D _nextRoomConfiner;

    private void OnTriggerEnter2D(Collider2D other)
    {
        if (other.CompareTag("Player"))
        {
            other.transform.position = _spawnPoint.position;
            // Switch camera confiner to new room bounds
            CinemachineVirtualCamera vcam = FindFirstObjectByType<CinemachineVirtualCamera>();
            CinemachineConfiner2D confiner = vcam.GetComponent<CinemachineConfiner2D>();
            confiner.m_BoundingShape2D = _nextRoomConfiner.m_BoundingShape2D;
        }
    }
}
```

## Wave System

```csharp
[System.Serializable]
public sealed class EnemyWave
{
    public List<SpawnEntry> Entries;
    public float DelayBeforeWave = 2f;
}

[System.Serializable]
public sealed class SpawnEntry
{
    public GameObject Prefab;
    public int Count;
    public float SpawnDelay = 0.5f;
}

public sealed class WaveManager : MonoBehaviour
{
    [SerializeField] private List<EnemyWave> _waves;
    [SerializeField] private Transform[] _spawnPoints;

    private int _currentWave;
    private int _enemiesAlive;

    public event System.Action<int> OnWaveStarted;
    public event System.Action OnAllWavesComplete;

    public void StartNextWave()
    {
        if (_currentWave >= _waves.Count)
        {
            OnAllWavesComplete?.Invoke();
            return;
        }

        StartCoroutine(SpawnWave(_waves[_currentWave]));
        OnWaveStarted?.Invoke(_currentWave);
        _currentWave++;
    }

    private IEnumerator SpawnWave(EnemyWave wave)
    {
        yield return new WaitForSeconds(wave.DelayBeforeWave);

        for (int i = 0; i < wave.Entries.Count; i++)
        {
            SpawnEntry entry = wave.Entries[i];
            for (int j = 0; j < entry.Count; j++)
            {
                Transform spawnPoint = _spawnPoints[Random.Range(0, _spawnPoints.Length)];
                Instantiate(entry.Prefab, spawnPoint.position, Quaternion.identity);
                _enemiesAlive++;
                yield return new WaitForSeconds(entry.SpawnDelay);
            }
        }
    }

    public void OnEnemyDied()
    {
        _enemiesAlive--;
        if (_enemiesAlive <= 0)
        {
            StartNextWave();
        }
    }
}
```

## Minimap

1. Create a secondary camera (orthographic, top-down, high Y)
2. Set it to render to a RenderTexture
3. Display RenderTexture on a UI RawImage
4. Camera follows player position (X/Z only)
5. Use layers to control what the minimap camera sees

## Projectile Patterns

- **Single:** straight line from muzzle
- **Spread:** 3-5 projectiles in a fan arc
- **Burst:** N projectiles with delay between each
- **Homing:** Lerp direction toward target each frame
- **Circular:** spawn ring of projectiles expanding outward

## Fog of War (Simple)

1. Full-screen quad with black texture
2. Reveal circle around player (shader: distance from player position → alpha)
3. Persistent reveal: write to reveal texture, never erase
4. Performance: use low-res render texture, blur the edges
