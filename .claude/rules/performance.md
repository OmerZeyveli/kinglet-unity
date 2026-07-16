# Performance Rules

## The Golden Rule

**Zero heap allocations in Update, FixedUpdate, and LateUpdate.**

Every allocation triggers GC, which causes frame spikes. Profile with Unity Profiler's GC Alloc column.

## Cache Everything

```csharp
// BAD — FindObjectOfType every frame
private void Update()
{
    Camera.main.WorldToScreenPoint(transform.position); // Camera.main calls FindObjectOfType
    GetComponent<Rigidbody>().AddForce(Vector3.up);
}

// GOOD — cache in Awake
private Camera _mainCamera;
private Rigidbody _rigidbody;

private void Awake()
{
    _mainCamera = Camera.main;
    _rigidbody = GetComponent<Rigidbody>();
}
```

Cache these in Awake — NEVER call in Update:
- `GetComponent<T>()` / `TryGetComponent<T>()`
- `Camera.main` (does FindObjectOfType internally)
- `transform` / `gameObject` (minor but adds up in hot loops)
- `Animator.StringToHash()` / `Shader.PropertyToID()` → `static readonly int` (UpperCamelCase)

## Avoid Allocations

| Allocates | Use Instead |
|-----------|------------|
| `new List<T>()` in Update | Pre-allocate, reuse with `.Clear()` |
| `new WaitForSeconds(n)` | Cache as field: `WaitForSeconds _wait = new(0.5f)` |
| `string + string` | `StringBuilder` or `string.Format` |
| `foreach` on non-List | `for` loop with index |
| `LINQ` (`.Where`, `.Select`, `.Any`) | Manual loops |
| `FindObjectOfType` | Cached reference or SO runtime set |
| `tag == "tag"` | `CompareTag("tag")` |
| `SendMessage` / `BroadcastMessage` | Direct reference or events |
| `Physics.RaycastAll` | `Physics.RaycastNonAlloc` with pre-allocated array |

## Physics

- Use non-allocating variants: `OverlapSphereNonAlloc`, `RaycastNonAlloc`, `SphereCastNonAlloc`
- Pre-allocate result arrays: `private RaycastHit[] _hitBuffer = new RaycastHit[16]`
- Physics queries in `FixedUpdate`, not `Update`

## Object Lifecycle

- Pool frequently instantiated objects — `ObjectPool<T>` or custom pool
- `SetActive(false)` to return to pool, not `Destroy`
- `DontDestroyOnLoad` sparingly — prefer bootstrapper scene

## Rendering & Draw Calls (NON-NEGOTIABLE)

**Draw call budget matters as much as GC.** The architect MUST plan rendering optimization from the start — not as an afterthought.

### The Draw Call Rule

Every unique Material + Mesh combination = 1 draw call. Always aim for the **lowest draw call count possible** — batch aggressively, atlas everything, share materials. There is no "good enough" number; fewer is always better.

### Sprite & Texture Atlasing (MANDATORY for 2D)

```
// BAD — 52 card sprites = 52 separate textures = 52+ draw calls
card_hearts_1.png, card_hearts_2.png, ... (individual files)

// GOOD — 1 sprite atlas = 1 draw call for all cards
SpriteAtlas "CardAtlas" containing all 52 cards + backs + UI elements
```

**Rules:**
- **All 2D sprites MUST use Sprite Atlases** — create atlases in `Assets/Art/Atlases/`
- Group by rendering layer: one atlas per logical group (cards, UI icons, environment tiles)
- Max atlas size: 2048x2048 (mobile) or 4096x4096 (desktop)
- Enable "Tight Packing" and "Allow Rotation" for optimal packing
- The architect MUST specify atlas grouping in the TDD

### Material Sharing

```csharp
// BAD — creates a material instance per object (breaks batching)
renderer.material.color = Color.red;  // .material clones the material!

// GOOD — shared material + MaterialPropertyBlock (preserves batching)
private static readonly int ColorId = Shader.PropertyToID("_Color");
private MaterialPropertyBlock _propBlock;

private void Awake()
{
    _propBlock = new MaterialPropertyBlock();
}

public void SetColor(Color color)
{
    _propBlock.SetColor(ColorId, color);
    _renderer.SetPropertyBlock(_propBlock);
}
```

**Rules:**
- NEVER access `renderer.material` — it clones the material and breaks batching
- Use `renderer.sharedMaterial` for read-only access
- Use `MaterialPropertyBlock` for per-instance property changes
- Share materials across objects wherever possible — fewer unique materials = fewer draw calls

### SRP Batcher & Batching

```csharp
// For URP/HDRP — SRP Batcher compatibility:
// Shaders must use CBUFFER blocks (Shader Graph does this automatically)
// All materials using the same shader variant batch together
```

**Rules:**
- **URP projects**: Ensure SRP Batcher is enabled (Project Settings → Graphics)
- **Sprites**: Use Sprite Atlas + same material = automatic batching
- **3D**: Enable GPU Instancing on materials for repeated meshes (trees, props, enemies)
- **Static objects**: Mark as "Batching Static" in inspector for static batching
- **Dynamic objects**: Keep same material + mesh for dynamic batching (< 300 vertices)
- The architect MUST specify batching strategy in the TDD

### UI Canvas Optimization

```
// BAD — one Canvas for everything
Canvas (root)
  ├─ HUD (updates every frame)
  ├─ PauseMenu (rarely changes)
  └─ ScorePopups (frequent spawns)

// GOOD — split by update frequency
Canvas_HUD (updates every frame)
Canvas_Static (pause menu, settings — rarely rebuilds)
Canvas_Popups (dynamic elements)
```

**Rules:**
- **Split Canvases by update frequency** — a single changing element rebuilds the ENTIRE Canvas mesh
- Static UI (backgrounds, labels that never change) on a separate Canvas
- Frequently updating UI (health bars, timers, scores) on their own Canvas
- Disable `Raycast Target` on elements that don't need click/touch detection
- Use `CanvasGroup.alpha = 0` + `blocksRaycasts = false` instead of `SetActive(false)` to avoid rebuild on re-enable
- Pool UI elements (popups, list items) — don't Instantiate/Destroy

### Overdraw

- Minimize overlapping transparent sprites — each layer is a separate draw
- Use opaque sprites where possible (no alpha)
- For particle effects: fewer large particles > many small particles
- Check overdraw with Scene View → Overdraw visualization mode

### Camera & Culling

- Set appropriate near/far clip planes — don't render what the camera can't see
- Use culling layers to exclude objects from cameras that don't need them
- For 2D: use `Sorting Layers` and `Order in Layer` — not Z-position hacks

### Architect Responsibility

The TDD MUST include a **Rendering Strategy** section covering:
1. How draw calls will be minimized (aim for the lowest count possible)
2. Atlas plan (which sprites go in which atlases)
3. Material sharing strategy
4. Batching approach (SRP Batcher, static, dynamic, GPU instancing)
5. UI Canvas split plan
6. Any known overdraw risks and mitigation

This is not optional. A game that runs at 10 FPS because of 500 draw calls is worse than a game with unoptimized C# that still hits 60 FPS.

### Developer Action Items (MANDATORY)

Agents cannot always create Unity assets directly (sprite atlases, material presets, texture import settings, lighting bakes, etc.). When rendering optimization requires manual Unity Editor work:

1. **Do NOT silently skip it.** If the game needs a sprite atlas and the agent can't create one, the agent MUST stop and tell the developer.
2. **Generate clear, step-by-step instructions** for the developer to follow in the Unity Editor. Be specific: which menu, which settings, which assets to include.
3. **Block progress on dependent work.** Do not write code that references an atlas or shared material that doesn't exist yet. Guide the developer to create the asset first, then continue.
4. **The architect includes a "Developer Setup Steps" section** in the TDD listing all manual optimization work the developer must do before or during implementation.
5. **The reviewer checks that these steps were completed.** If sprite atlases were planned but don't exist, the review FAILS with instructions for the developer.

Example guidance format:
```
## Developer Action Required: Sprite Atlas Setup

The game requires sprite atlases for optimal draw call count. Please create these in Unity Editor:

1. Right-click in Project window → Create → 2D → Sprite Atlas
2. Name it "CardAtlas", save to Assets/Art/Atlases/
3. In the Inspector:
   - Add folder "Assets/Art/Cards" to "Objects for Packing"
   - Set "Max Texture Size" to 2048
   - Enable "Tight Packing"
   - Enable "Allow Rotation"
   - Click "Pack Preview" to verify all sprites fit
4. Repeat for "UIAtlas" with Assets/Art/UI/

Until these atlases exist, every card/UI element is a separate draw call.
```

This applies to ALL optimization assets the agent can't create: sprite atlases, material presets, texture compression settings, lightmap baking, occlusion culling setup, LOD groups, etc.

## Debug

- No `Debug.Log` in production — use `[Conditional("UNITY_EDITOR")]` wrapper
- Strip debug code with scripting defines, not runtime checks
