---
name: physics
description: "Unity physics — non-allocating queries, collision layers, FixedUpdate discipline, continuous collision detection, character controllers, joints."
---

# Physics System

*Written against Unity 6000.0, current as of 2026-08-04.*

## Boundary with the rules

`.claude/rules/performance.md` binds non-allocating queries (`RaycastNonAlloc`, `OverlapSphereNonAlloc`,
`SphereCastNonAlloc` with pre-allocated buffers) and FixedUpdate placement for physics work. This skill
carries the API detail — layer setup, collision detection modes, collision-vs-trigger callbacks, joints,
2D equivalents. Where this skill and `performance.md` disagree, the rule wins and this skill is what is
out of date.

**The rule names the 3D family.** `OverlapSphereNonAlloc` and `SphereCastNonAlloc` exist only on
`Physics`; only `RaycastNonAlloc` appears in both families. What "non-allocating" means on `Physics2D`
is this skill's business, and in Unity 6 the answer is **not** the same suffix — see *2D Physics
Equivalents* below. That is a gap the rule does not cover, not a disagreement with it.

## FixedUpdate Discipline

All physics code goes in `FixedUpdate`. Input reading happens in `InputView.Update` (see architecture rules) and is forwarded to the System, which applies forces in `FixedUpdate` from the cached value.

```csharp
// InputView.cs — reads input in Update, forwards to System
private void Update()
{
    Vector2 moveInput = _controls.Player.Move.ReadValue<Vector2>();
    _playerSystem.SetMoveInput(moveInput);
}

// PlayerView.cs — applies physics in FixedUpdate from System-owned cached input
private Vector2 _moveInput;

public void SetMoveInput(Vector2 input) => _moveInput = input;

private void FixedUpdate()
{
    _rigidbody.AddForce(_moveInput * _force);
}
```

## Non-Allocating Queries

Everything in this section is the **3D** family, on `Physics`. Do not translate the `NonAlloc` suffix
into `Physics2D` — it is retired there. See *2D Physics Equivalents* below before writing a 2D query.

```csharp
// Pre-allocate buffers
private static readonly RaycastHit[] _hitBuffer = new RaycastHit[16];
private static readonly Collider[] _overlapBuffer = new Collider[32];

// Raycast
int hitCount = Physics.RaycastNonAlloc(origin, direction, _hitBuffer, maxDistance, layerMask);
for (int i = 0; i < hitCount; i++)
{
    RaycastHit hit = _hitBuffer[i];
    // Process hit
}

// Overlap sphere (area detection)
int overlapCount = Physics.OverlapSphereNonAlloc(center, radius, _overlapBuffer, layerMask);

// Sphere cast (fat raycast)
int castCount = Physics.SphereCastNonAlloc(origin, radius, direction, _hitBuffer, maxDistance, layerMask);
```

## Layer Collision Matrix

```csharp
// Ignore collisions between layers programmatically
Physics.IgnoreLayerCollision(playerLayer, pickupLayer, true);

// Or configure in Edit > Project Settings > Physics > Layer Collision Matrix
```

Layer organization:
```
6: Player
7: Ground
8: Enemy
9: Projectile
10: Trigger (no physics collision, triggers only)
11: Interactable
```

## Collision Detection Modes

| Mode | Use When |
|------|----------|
| Discrete | Slow objects (default) |
| Continuous | Fast objects that might tunnel through thin colliders |
| Continuous Dynamic | Fast objects colliding with other fast objects |
| Continuous Speculative | Good balance of accuracy and performance |

## Collision vs Trigger Callbacks

```csharp
// Collision (both have colliders, at least one has Rigidbody, neither is trigger)
private void OnCollisionEnter(Collision collision) { }
private void OnCollisionStay(Collision collision) { }
private void OnCollisionExit(Collision collision) { }

// Trigger (at least one collider has isTrigger = true)
private void OnTriggerEnter(Collider other) { }
private void OnTriggerStay(Collider other) { }
private void OnTriggerExit(Collider other) { }
```

## Physics.SyncTransforms

After moving a transform directly, physics queries won't reflect the new position until the next physics step. Force sync:
```csharp
transform.position = newPosition;
Physics.SyncTransforms(); // Now raycasts see the new position
```

## Rigidbody Configuration

- **Interpolation:** `Interpolate` for player (smooths between physics steps), `None` for others
- **Constraints:** Freeze rotation for 2D-like behavior in 3D
- **Collision Detection:** Continuous for fast-moving objects

## 2D Physics Equivalents

| 3D | 2D |
|----|-----|
| `Rigidbody` | `Rigidbody2D` |
| `BoxCollider` | `BoxCollider2D` |
| `Physics.Raycast` | `Physics2D.Raycast` |
| `Physics.OverlapSphereNonAlloc` | `Physics2D.OverlapCircle` — **not** `…NonAlloc`, see below |
| `OnCollisionEnter(Collision)` | `OnCollisionEnter2D(Collision2D)` |
| `OnTriggerEnter(Collider)` | `OnTriggerEnter2D(Collider2D)` |

### The `NonAlloc` suffix is 3D-only in Unity 6

**Do not carry `*NonAlloc` across into `Physics2D`.** The suffix is deprecated in the 2D family and
untouched in the 3D one, and that asymmetry is the whole trap: the two families read as mirror images
and are not. This row taught `Physics2D.OverlapCircleNonAlloc` until 2026-08-15 and survived review
because it looked internally consistent — a correct left column beside a dead right one.

| Call | Obsolete overloads | Unity's message |
|---|---|---|
| `Physics.RaycastNonAlloc` | 0 / 8 | — |
| `Physics.OverlapSphereNonAlloc` | 0 / 3 | — |
| `Physics2D.RaycastNonAlloc` | **4 / 5** | *"deprecated. Use Physics2D.Raycast instead."* |
| `Physics2D.OverlapCircleNonAlloc` | **4 / 4** | *"deprecated. Use Physics2D.OverlapCircle instead."* |
| `Physics2D.CircleCastNonAlloc` | **5 / 5** | *"deprecated. Use Physics2D.CircleCast instead."* |
| `Physics2D.BoxCastNonAlloc` | **5 / 5** | *"deprecated. Use Physics2D.BoxCast instead."* |
| `Physics2D.OverlapBoxNonAlloc` | **4 / 4** | *"deprecated. Use Physics2D.OverlapBox instead."* |

Reflected off a live Unity 6000.0.68f1 editor on 2026-08-14. The plain 2D names carry no obsolete
overload at all — `Physics2D.Raycast` 0 / 8, `Physics2D.OverlapCircle` 0 / 6.

Unity 6 gave those plain names overloads taking a `ContactFilter2D` plus a `List<T>` or a results
array, so **the plain name is the non-allocating call now** and the suffix was retired. Allocation
discipline is unchanged; only the spelling moved.

The exact `ContactFilter2D` overload signatures are **not** reproduced here — nothing in this toolkit
has ever executed one, and a guessed parameter order is worse than no sample. Read Unity's 6000.0
`Physics2D` scripting reference for the overload you want before writing the call. (Same reason the
`urp-pipeline` skill declines to reproduce the render graph pass API.)

## Pitfalls

| Mistake | Why it is tempting | What it costs | Source |
|---|---|---|---|
| Trusting a `RaycastNonAlloc`/`OverlapSphereNonAlloc` result count without checking it against the buffer's length | The non-allocating call looks like a drop-in replacement for the allocating one — same parameters, just faster | A full buffer does not grow and does not report overflow. The returned hit count caps at the buffer's `Length`; any hits beyond that are silently dropped, not reported as an error. A `RaycastHit[16]` in a dense scene can under-report hits with no warning, and the bug only appears once the scene gets crowded enough to fill the buffer | `.claude/rules/performance.md`: "Pre-allocate result arrays" — the buffer is fixed-size by design, which is exactly what makes the silent truncation possible if the cap is never checked |

## Joints

| Joint | Use |
|-------|-----|
| Fixed | Weld objects together |
| Hinge | Doors, wheels |
| Spring | Bouncy connections |
| Configurable | Full control over all axes |
| Character | Character controller with physics |
