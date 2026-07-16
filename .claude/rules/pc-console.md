# PC / Console Rules

This is the **cloud-nine-unity** overlay's platform addendum. It does **not** replace any ECU
rule. ECU's `architecture.md`, `csharp-unity.md`, `performance.md`, `serialization.md`, and
`unity-specifics.md` remain the binding spine — **when anything here and an ECU rule appear to
conflict, the ECU rule wins.** This file only neutralizes mobile-specific assumptions and adds
desktop/console input and performance notes.

## Mobile Assumptions Do Not Apply

ECU ships a mobile-oriented skill (`.claude/skills/platform/mobile/`) and some examples in
`performance.md` use mobile framing (TBDR/tile GPUs, ASTC textures, thermal throttling, very low
draw-call ceilings, touch input, safe-area handling, <100 MB build-size targets). **On a
PC/console project, ignore those mobile-specific ceilings and constraints.** They are not wrong
for phones — they simply are not your platform.

> Optional cleanup: if you never ship to mobile, you may delete
> `.claude/skills/platform/mobile/` and the `genre/hyper-casual` and `genre/endless-runner`
> skills. Leaving them in place is harmless — they just won't trigger on a PC/console project.

The architectural performance rules in `performance.md` that are **platform-independent still
fully apply**: zero allocations in `Update`/`FixedUpdate`/`LateUpdate`, cache `GetComponent` /
`Camera.main`, `MaterialPropertyBlock` over `.material`, sprite atlasing, batching, and Canvas
splitting. "Fewer draw calls is always better" remains true on every platform.

## Input — Keyboard/Mouse and Gamepad (no touch)

- **Primary inputs are keyboard + mouse and gamepad.** There is no touch, no on-screen joystick,
  no gyro, and no safe-area. Do not add touch controls or 44×44 tap-target reasoning.
- Use the **New Input System** exactly as ECU's `unity-specifics.md` mandates (legacy `Input.*`
  is blocked). Author action maps that work for **both** keyboard/mouse and gamepad; the
  `InputView` is the only place that touches `PlayerControls`.
- **Support control rebinding** (key + button remapping) — it is a baseline expectation on PC and
  a common console requirement. Drive rebinding from the `InputView`; keep Systems input-agnostic
  (they receive `SetMoveInput(Vector2)`, `Jump()`, etc., and never know the device).
- Handle **device switching** gracefully (player swaps from keyboard to gamepad mid-session) and
  reflect the active device in UI prompts where relevant.
- Console certification commonly requires controller-disconnect handling and a "press any button"
  / controller-assignment flow — design for it from the start, don't retrofit.

## Performance — Desktop/Console Targets

- **Frame-rate target:** 60 FPS is the baseline. On PC also account for **high-refresh displays**
  (120/144 Hz+) — decouple simulation from rendering and don't hard-assume 60. Console targets are
  usually 30 or 60 FPS depending on a quality/performance mode; budget for the mode you commit to.
- **Draw-call and memory budgets are higher than mobile**, but the discipline is the same: batch
  aggressively, atlas, share materials, and use the SRP Batcher / GPU instancing. Higher headroom
  is not an excuse to skip batching.
- **PC hardware varies enormously.** Plan for **graphics quality / settings scaling** (resolution
  scale, shadow/texture quality, VSync, frame-rate cap) so the game runs on both low-end and
  high-end machines. Consoles are fixed targets — tune to the specific hardware.
- **Resolution and aspect ratios:** support **multiple resolutions and aspect ratios**, including
  **ultrawide (21:9)** on PC. Anchor UI for a range of aspect ratios; don't hardcode 16:9 layout.
- **No thermal/battery/build-size obsession.** Drop mobile concerns like thermal throttling
  (Adaptive Performance), aggressive texture compression for download size, and tiny memory
  ceilings. Optimize for steady frame-time and load times instead.

## Everything Else Defers to ECU

For C# style, the Model-View-System architecture, VContainer (DI), MessagePipe (messaging),
UniTask (async), serialization safety (`[FormerlySerializedAs]`, `== null`), and all other
conventions, follow ECU's rules unchanged. This addendum is intentionally narrow.
