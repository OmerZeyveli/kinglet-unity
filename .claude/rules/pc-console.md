# PC / Console Rules

The platform spec for this toolkit. cloud-nine-unity ships **no mobile content** — the mobile skill
and the mobile genre skills were removed at build time, not disabled (see `provenance-skip.tsv`), and
the agents' mobile guidance was rewritten. So this file does not neutralize anything; it states what
we target.

Precedence: `architecture.md`, `csharp-unity.md`, `performance.md`, `serialization.md`, and
`unity-specifics.md` are the binding spine. This file adds platform specifics on top of them — it
does not override them. If something here appears to contradict a spine rule, the spine rule wins and
the contradiction is a bug in this file; report it.

## Targets

- **PC** (Steam / Epic / standalone) and **console**. No mobile, no WebGL, no touch.
- **Unity 6**, URP unless a project states otherwise.
- **60 FPS is the baseline.** On PC also account for high-refresh displays (120/144 Hz+) — decouple
  simulation from rendering and never hard-assume 60. Consoles usually ship a 30 or 60 FPS
  quality/performance mode; budget for the mode you commit to.

## Input — Keyboard/Mouse and Gamepad

- **Primary inputs are keyboard + mouse and gamepad.** There is no touch, no on-screen joystick, no
  gyro, no safe area. Do not add touch controls or 44×44 tap-target reasoning.
- Use the **New Input System** as `unity-specifics.md` mandates (legacy `Input.*` is blocked by a
  hook). Author action maps that work for **both** keyboard/mouse and gamepad; the `InputView` is the
  only place that touches `PlayerControls`.
- **Support rebinding** (key + button remapping). It is a baseline expectation on PC and a common
  console requirement. Drive it from the `InputView`; keep Systems input-agnostic — they receive
  `SetMoveInput(Vector2)`, `Jump()`, and never learn the device.
- **Handle device switching** mid-session (player drops the keyboard, picks up a pad) and reflect the
  active device in UI prompts. The `input-system` skill has a `DeviceDetector` worth copying.
- Console cert commonly requires controller-disconnect handling and a "press any button" /
  controller-assignment flow. Design for it from the start; retrofitting is painful.

## Rendering — what you may use

Compute shaders and VFX Graph are **fully available on PC and console** and are encouraged where they
beat CPU-side work: particles, culling, post-processing, GPU-side simulation. Shader Model 5.0+ is a
safe baseline on both. (If you find guidance in this repo saying otherwise, it is a leftover from the
mobile-targeted upstream — treat it as a bug and report it.)

MSAA, HDR, higher shadow-cascade counts, and real-time shadows are all affordable. Budget them rather
than avoiding them.

## Performance — desktop/console targets

- **PC hardware varies enormously, and min-spec is what decides who can play.** Budget for the low
  end first, then let the high end scale up. Ship graphics **quality settings** — resolution scale,
  shadow/texture quality, VSync, frame-rate cap — and make sure the min-spec preset actually holds
  60 FPS.
- **GPU vendor variance is real.** NVIDIA, AMD, and Intel differ in driver behaviour and precision. A
  shader that is fast on one can stall on another. Test all three; your dev machine is one data point.
- **Consoles are fixed targets** — profile on the hardware and tune to it rather than guessing from a
  dev PC.
- **Higher headroom is not an excuse to skip batching.** Draw-call ceilings are far above mobile's,
  but the SRP Batcher, GPU instancing, static batching, atlasing, and shared materials are still free
  frame time. "Fewer draw calls is always better" holds on every platform.
- **Fill rate scales with pixels.** Profile at 4K and 3440×1440, not just 1080p. Overdraw that is
  invisible at 1080p can cost real milliseconds at 4K.
- **Texture compression:** BC7 for albedo, BC5 for normals on desktop. Consoles have their own
  preferred formats.
- **No thermal/battery/build-size obsession.** Drop Adaptive Performance, download-size compression,
  and tiny memory ceilings. Optimise for steady frame-time and load times instead.
- The platform-independent rules in `performance.md` apply in full: zero allocations in
  `Update`/`FixedUpdate`/`LateUpdate`, cache `GetComponent` / `Camera.main`, `MaterialPropertyBlock`
  over `.material`, Canvas splitting.

## Display and windowing

- **Support multiple resolutions and aspect ratios, including ultrawide (21:9).** Anchor UI for a
  range of aspect ratios; never hardcode a 16:9 layout.
- **Handle focus loss.** Alt-tab, Windows key, overlay open — pause or degrade gracefully, and do not
  swallow input on regain.
- **Multi-monitor:** let the player choose the display; do not assume the primary.
- **4K and high DPI:** account for UI scaling, and consider DLSS/FSR/TAAU where the pipeline supports
  it.

## Everything Else

For C# style, Model-View-System, VContainer (DI), MessagePipe (messaging), UniTask (async), and
serialization safety (`[FormerlySerializedAs]`, `== null`), follow the spine rules unchanged. This
addendum is intentionally narrow.
