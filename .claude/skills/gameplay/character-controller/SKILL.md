---
name: character-controller
description: "2D and 3D character controller patterns — coyote time, input buffering, variable jump, wall slide/jump, dash, slopes, stairs, camera-relative movement. Load when implementing player movement."
globs: ["**/Player*.cs", "**/Character*.cs", "**/Movement*.cs", "**/Controller*.cs"]
---

# Character Controller Patterns

Comprehensive reference for building responsive, game-feel-polished character controllers in Unity. Covers both 2D platformer and 3D action game patterns.

## 2D Character Controller

### Ground Detection

Use an overlap circle at the character's feet rather than relying on collision callbacks. This gives frame-accurate ground state.

```csharp
[Header("Ground Check")]
[SerializeField] private Transform groundCheckPoint;
[SerializeField] private float groundCheckRadius = 0.15f;
[SerializeField] private LayerMask groundLayer;

private bool _isGrounded;

private void CheckGround()
{
    _isGrounded = Physics2D.OverlapCircle(
        groundCheckPoint.position,
        groundCheckRadius,
        groundLayer
    );
}
```

Place `groundCheckPoint` as a child transform at the bottom of the character sprite. Keep the radius small to avoid false positives on walls.

### Coyote Time

Allow the player to jump for a brief window after walking off a ledge. This forgives slight mistiming and makes platforming feel generous rather than punishing.

```csharp
[Header("Coyote Time")]
[SerializeField] private float coyoteTimeDuration = 0.1f;

private float _coyoteTimeCounter;

private void Update()
{
    if (_isGrounded)
    {
        _coyoteTimeCounter = coyoteTimeDuration;
    }
    else
    {
        _coyoteTimeCounter -= Time.deltaTime;
    }

    if (_jumpPressed && _coyoteTimeCounter > 0f)
    {
        ExecuteJump();
        _coyoteTimeCounter = 0f; // Consume coyote time
    }
}
```

A typical value is 0.08 to 0.15 seconds. Higher feels more forgiving; lower feels tighter. Playtest to find the sweet spot for your game's pace.

### Input Buffering

Queue a jump input so it fires the moment the player lands, even if they pressed the button a few frames early. Combined with coyote time, this eliminates most "I pressed jump but nothing happened" complaints.

```csharp
[Header("Input Buffering")]
[SerializeField] private float jumpBufferDuration = 0.12f;

private float _jumpBufferCounter;

private void Update()
{
    // Buffer the input
    if (_jumpPressedThisFrame)
    {
        _jumpBufferCounter = jumpBufferDuration;
    }
    else
    {
        _jumpBufferCounter -= Time.deltaTime;
    }

    // Consume buffer when grounded (or in coyote time)
    if (_jumpBufferCounter > 0f && _coyoteTimeCounter > 0f)
    {
        ExecuteJump();
        _jumpBufferCounter = 0f;
        _coyoteTimeCounter = 0f;
    }
}
```

### Variable Jump Height

Cut the jump short when the player releases the button early. This gives the player fine control over arc height.

```csharp
[Header("Variable Jump")]
[SerializeField] private float jumpForce = 14f;
[SerializeField] private float jumpCutMultiplier = 0.4f;

private Rigidbody2D _rb;

private void ExecuteJump()
{
    // Reset vertical velocity before applying force for consistent jump height
    _rb.velocity = new Vector2(_rb.velocity.x, 0f);
    _rb.AddForce(Vector2.up * jumpForce, ForceMode2D.Impulse);
}

private void Update()
{
    // When the player releases jump while still moving upward, cut velocity
    if (_jumpReleasedThisFrame && _rb.velocity.y > 0f)
    {
        _rb.velocity = new Vector2(
            _rb.velocity.x,
            _rb.velocity.y * jumpCutMultiplier
        );
    }
}
```

The `jumpCutMultiplier` controls how much velocity is retained. A value of 0.4 means releasing early yields roughly 40% of max jump height. Tune this alongside gravity scale.

### Wall Slide and Wall Jump

Detect walls with a horizontal raycast or box overlap. Apply reduced gravity while sliding, then launch away from the wall on jump.

```csharp
[Header("Wall Interaction")]
[SerializeField] private Transform wallCheckPoint;
[SerializeField] private float wallCheckDistance = 0.3f;
[SerializeField] private LayerMask wallLayer;
[SerializeField] private float wallSlideSpeed = 2f;
[SerializeField] private Vector2 wallJumpForce = new Vector2(12f, 16f);
[SerializeField] private float wallJumpLockTime = 0.15f;

private bool _isTouchingWall;
private bool _isWallSliding;
private float _wallJumpLockCounter;
private int _wallDirection; // -1 left, 1 right

private void CheckWall()
{
    _isTouchingWall = Physics2D.Raycast(
        wallCheckPoint.position,
        Vector2.right * transform.localScale.x,
        wallCheckDistance,
        wallLayer
    );

    // Wall slide when airborne, touching wall, and holding toward it
    _isWallSliding = _isTouchingWall && !_isGrounded && _moveInput.x != 0f;
}

private void ApplyWallSlide()
{
    if (!_isWallSliding) return;

    // Clamp downward velocity to slide speed
    if (_rb.velocity.y < -wallSlideSpeed)
    {
        _rb.velocity = new Vector2(_rb.velocity.x, -wallSlideSpeed);
    }

    _wallDirection = transform.localScale.x > 0 ? 1 : -1;
}

private void WallJump()
{
    if (!_isWallSliding) return;

    // Jump away from wall
    _rb.velocity = Vector2.zero;
    _rb.AddForce(new Vector2(-_wallDirection * wallJumpForce.x, wallJumpForce.y),
        ForceMode2D.Impulse);

    // Temporarily lock horizontal input so the player does not immediately
    // steer back into the wall
    _wallJumpLockCounter = wallJumpLockTime;
}
```

The input lock after a wall jump is critical. Without it, players holding toward the wall will negate the horizontal push and slide back down immediately.

### Dash Mechanic

A short burst of speed with optional invincibility frames. Use a cooldown to prevent spamming.

```csharp
[Header("Dash")]
[SerializeField] private float dashSpeed = 24f;
[SerializeField] private float dashDuration = 0.12f;
[SerializeField] private float dashCooldown = 0.6f;
[SerializeField] private bool dashGrantsInvincibility = true;

private bool _isDashing;
private float _dashCooldownCounter;

private IEnumerator DashCoroutine(Vector2 direction)
{
    _isDashing = true;
    _dashCooldownCounter = dashCooldown;

    if (dashGrantsInvincibility)
        Physics2D.IgnoreLayerCollision(playerLayer, enemyLayer, true);

    _rb.gravityScale = 0f;
    _rb.velocity = direction.normalized * dashSpeed;

    yield return new WaitForSeconds(dashDuration);

    _rb.gravityScale = _defaultGravityScale;
    _isDashing = false;

    if (dashGrantsInvincibility)
        Physics2D.IgnoreLayerCollision(playerLayer, enemyLayer, false);
}
```

### One-Way Platforms

Use Unity's `PlatformEffector2D` component for pass-through platforms. The player can jump up through them and stand on top.

- Add `PlatformEffector2D` to the platform GameObject.
- Set `Surface Arc` to 180 (only the top is solid).
- Enable `Use One Way` on the effector.
- On the platform's `Collider2D`, check `Used By Effector`.
- To drop through, temporarily disable the collider or set the effector's `rotationalOffset` to 180 for a brief period.

```csharp
private IEnumerator DropThroughPlatform(Collider2D platformCollider)
{
    platformCollider.enabled = false;
    yield return new WaitForSeconds(0.25f);
    platformCollider.enabled = true;
}
```

### State Machine Integration

Organize movement code with explicit states rather than nested booleans. Each state has its own enter/exit/update logic.

Recommended player states for a 2D platformer:
- **Idle** - grounded, no input
- **Run** - grounded, horizontal input
- **Jump** - ascending after jump
- **Fall** - airborne, descending
- **WallSlide** - against wall, descending slowly
- **Dash** - mid-dash, ignoring gravity
- **Hurt** - knocked back, input disabled briefly
- **Dead** - no input, play death animation

See the `state-machine` skill for the generic FSM implementation that works with these states.

---

## 3D Character Controller

### CharacterController vs Rigidbody

**CharacterController (built-in):**
- Simpler setup, `Move()` and `SimpleMove()` methods
- Built-in slope and step handling via `slopeLimit` and `stepOffset`
- No physics interactions by default (you push nothing, nothing pushes you)
- Best for: first/third person games where you want full control

**Rigidbody-based:**
- Interacts with physics objects naturally
- Requires manual ground detection, slope handling
- Must use `FixedUpdate` for movement to avoid jitter
- Best for: games with heavy physics interaction (pushing crates, riding platforms)

### Ground Detection (3D)

SphereCast from the bottom of the character for reliable ground checks.

```csharp
[Header("Ground Check")]
[SerializeField] private float groundCheckDistance = 0.2f;
[SerializeField] private float groundCheckRadius = 0.3f;
[SerializeField] private LayerMask groundLayer;

private bool _isGrounded;
private RaycastHit _groundHit;

private void CheckGround()
{
    Vector3 origin = transform.position + Vector3.up * groundCheckRadius;

    _isGrounded = Physics.SphereCast(
        origin,
        groundCheckRadius,
        Vector3.down,
        out _groundHit,
        groundCheckDistance,
        groundLayer
    );
}
```

### Slope Handling

Prevent the character from sliding on acceptable slopes and force sliding on steep ones.

```csharp
[Header("Slopes")]
[SerializeField] private float maxSlopeAngle = 45f;
[SerializeField] private float slopeSlideSpeed = 8f;

private void HandleSlopes()
{
    if (!_isGrounded) return;

    float angle = Vector3.Angle(Vector3.up, _groundHit.normal);

    if (angle > maxSlopeAngle)
    {
        // Too steep: slide down
        Vector3 slideDirection = Vector3.ProjectOnPlane(Vector3.down, _groundHit.normal).normalized;
        _rb.AddForce(slideDirection * slopeSlideSpeed, ForceMode.Acceleration);
    }
    else if (angle > 0f)
    {
        // Walkable slope: project movement onto slope surface
        // This prevents the character from bouncing when walking downhill
        _moveDirection = Vector3.ProjectOnPlane(_moveDirection, _groundHit.normal).normalized
                         * _moveDirection.magnitude;
    }
}
```

### Stair Handling

For Rigidbody-based controllers, use a forward raycast at step height to detect stairs, then teleport the character up.

```csharp
[Header("Stairs")]
[SerializeField] private float stepHeight = 0.35f;
[SerializeField] private float stepCheckDepth = 0.4f;

private void HandleStairs()
{
    if (!_isGrounded || _moveDirection.magnitude < 0.01f) return;

    Vector3 lowerOrigin = transform.position + Vector3.up * 0.05f;
    Vector3 upperOrigin = transform.position + Vector3.up * stepHeight;

    // Check if something blocks at foot level
    bool lowerBlocked = Physics.Raycast(lowerOrigin, _moveDirection.normalized,
        stepCheckDepth, groundLayer);

    // Check if space is clear at step height
    bool upperClear = !Physics.Raycast(upperOrigin, _moveDirection.normalized,
        stepCheckDepth, groundLayer);

    if (lowerBlocked && upperClear)
    {
        transform.position += Vector3.up * stepHeight;
    }
}
```

### Camera-Relative Movement

Transform raw input so "forward" means "toward where the camera is looking," not world-space forward.

```csharp
[SerializeField] private Transform cameraTransform;

private Vector3 GetCameraRelativeMovement(Vector2 input)
{
    Vector3 camForward = cameraTransform.forward;
    Vector3 camRight = cameraTransform.right;

    // Flatten to horizontal plane
    camForward.y = 0f;
    camRight.y = 0f;
    camForward.Normalize();
    camRight.Normalize();

    return camForward * input.y + camRight * input.x;
}
```

### Gravity with Variable Fall Speed

Apply stronger gravity when falling for snappier, more responsive movement.

```csharp
[Header("Gravity")]
[SerializeField] private float gravityScale = 2.5f;
[SerializeField] private float fallMultiplier = 3.5f;
[SerializeField] private float maxFallSpeed = 30f;

private void ApplyGravity()
{
    float multiplier = _rb.velocity.y < 0f ? fallMultiplier : gravityScale;
    Vector3 gravity = Physics.gravity * (multiplier - 1f); // -1 because Unity already applies 1x
    _rb.AddForce(gravity, ForceMode.Acceleration);

    // Clamp fall speed
    if (_rb.velocity.y < -maxFallSpeed)
    {
        _rb.velocity = new Vector3(_rb.velocity.x, -maxFallSpeed, _rb.velocity.z);
    }
}
```

---

## Input System Integration

Use Unity's new Input System for rebindable, multi-device input.

### Action Map Setup

Create an Input Action Asset with these actions for a typical controller:

| Action    | Type            | Binding Examples                  |
|-----------|-----------------|-----------------------------------|
| Move      | Value (Vector2) | WASD, Left Stick                  |
| Jump      | Button          | Space, South Button (A/Cross)     |
| Dash      | Button          | Shift, West Button (X/Square)     |
| Attack    | Button          | Mouse Left, East Button (B/Circle)|
| Interact  | Button          | E, North Button (Y/Triangle)      |

### Reading Input

Read input in `Update` for responsiveness. Apply physics forces in `FixedUpdate`.

```csharp
using UnityEngine;
using UnityEngine.InputSystem;

public class PlayerInputHandler : MonoBehaviour
{
    private PlayerInputActions _actions;
    private Vector2 _moveInput;
    private bool _jumpPressed;
    private bool _jumpReleased;
    private bool _dashPressed;

    private void Awake()
    {
        _actions = new PlayerInputActions();
    }

    private void OnEnable()
    {
        _actions.Gameplay.Enable();

        _actions.Gameplay.Jump.performed += ctx => _jumpPressed = true;
        _actions.Gameplay.Jump.canceled += ctx => _jumpReleased = true;
        _actions.Gameplay.Dash.performed += ctx => _dashPressed = true;
    }

    private void OnDisable()
    {
        _actions.Gameplay.Disable();
    }

    private void Update()
    {
        _moveInput = _actions.Gameplay.Move.ReadValue<Vector2>();

        // Process jump, dash, etc. (coyote time, buffering happens here)
        ProcessJump();
        ProcessDash();
    }

    private void LateUpdate()
    {
        // Clear one-shot flags at end of frame
        _jumpPressed = false;
        _jumpReleased = false;
        _dashPressed = false;
    }

    private void FixedUpdate()
    {
        // Apply movement forces here
        ApplyMovement(_moveInput);
        ApplyGravity();
    }
}
```

**Key rule:** Never read `performed` callbacks in `FixedUpdate`. Physics ticks and render frames do not align, so you can miss button presses. Read in `Update`, store flags, consume in `FixedUpdate`.

---

## Practical Tips

- **Acceleration and deceleration curves** feel better than instant max speed. Use `Mathf.MoveTowards` or `Mathf.Lerp` on horizontal velocity.
- **Separate horizontal and vertical velocity** when manipulating movement. Never zero out the full velocity vector when you only mean to affect one axis.
- **Expose tuning values in the Inspector** with `[SerializeField]` and `[Header]` attributes. Movement feel is found through iteration, not calculation.
- **Use `Time.deltaTime`** in Update. In FixedUpdate, `Time.deltaTime` automatically returns `Time.fixedDeltaTime`, so it works in both contexts.
- **Ghost platforms** (where the player falls through solid ground) usually mean the ground check radius is too small or the character is moving too fast. Increase `Physics2D.velocityIterations` or use continuous collision detection.
- **Record and replay input** for debugging movement bugs. Store input frames in a list and replay them to reproduce issues deterministically.
