---
name: cinemachine
description: "Cinemachine camera system — virtual cameras, FreeLook, blending, noise profiles, state-driven cameras, confiner, follow/aim behaviors."
---

# Cinemachine

## Setup

1. Add `CinemachineBrain` component to Main Camera
2. Create Virtual Cameras — Brain auto-blends to highest priority

## Virtual Camera Components

**Body (follow):**
- `Transposer` — 3D offset follow (configurable damping)
- `Framing Transposer` — 2D/screen-space follow (dead zone, soft zone)
- `Orbital Transposer` — orbit around target (user input rotates)
- `Tracked Dolly` — follow a path

**Aim (look at):**
- `Composer` — keep target in frame with dead/soft zones
- `Group Composer` — frame a group of targets
- `Hard Look At` — no damping, instant look
- `POV` — player-controlled rotation (FPS)

## Common Setups

### 2D Platformer Camera
```
Virtual Camera:
  Body: Framing Transposer
    - Screen X/Y: 0.5 (center)
    - Dead Zone Width: 0.1, Height: 0.1
    - Damping: X=1, Y=0.5
  Follow: Player Transform
  Add Extension: CinemachineConfiner2D
    - Bounding Shape: PolygonCollider2D (room bounds)
```

### 3D Third-Person Camera
```
FreeLook Camera:
  Follow: Player Transform
  Look At: Player Head/Chest
  Top/Middle/Bottom Rig:
    - Height, Radius per rig
    - Composer aim in each rig
  X Axis: Input from mouse/stick (orbiting)
  Y Axis: Input from mouse/stick (elevation)
```

### State-Driven Camera (Animator)
```
State-Driven Camera:
  Animated Target: Player Animator
  States:
    Idle → VCam_Idle (wide shot)
    Run → VCam_Run (further back)
    Combat → VCam_Combat (over shoulder)
```

## Camera Blending

- Default blend: 2 seconds, EaseInOut
- Custom blends per transition (from VCam A to VCam B)
- Cut (0 seconds) for instant switches

## Cinemachine Impulse (Screen Shake)

```csharp
// Source: generates impulse
[SerializeField] private CinemachineImpulseSource _impulseSource;

public void OnExplosion()
{
    _impulseSource.GenerateImpulse();
}
```

Add `CinemachineImpulseListener` extension to virtual cameras that should respond.

## Noise (Handheld Feel)

Add `CinemachineBasicMultiChannelPerlin` to virtual camera:
- Profile: `6D Shake` or `Handheld_normal_mild`
- Amplitude/Frequency for intensity

## Code Control

```csharp
// Switch cameras by priority
_combatCamera.Priority = 20; // Higher = active
_exploreCamera.Priority = 10;

// Change follow target
_virtualCamera.Follow = newTarget;
_virtualCamera.LookAt = newTarget;
```

## Confiner

- **2D:** `CinemachineConfiner2D` + `PolygonCollider2D` (set collider to trigger, non-physics layer)
- **3D:** `CinemachineConfiner` + `BoxCollider` or `MeshCollider` volume
