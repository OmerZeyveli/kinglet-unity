---
name: unity-optimize
description: "Profile and optimize performance — uses MCP profiler for frame timing, memory, rendering stats. Identifies bottlenecks and applies fixes."
user-invocable: true
args: focus_area
---

# /unity-optimize — Performance Optimization

Optimize the project's performance. Focus area: **$ARGUMENTS**

## Workflow

Use the `unity-optimizer` agent to:

### Step 1: Profile
```
manage_profiler → start session, capture frame timing
manage_graphics → get rendering stats (draw calls, batches, triangles)
manage_profiler → memory snapshot
```

### Step 2: Identify Bottleneck Type
- **CPU-bound** — GC allocations, expensive Update loops, physics
- **GPU-bound** — too many draw calls, overdraw, complex shaders
- **Memory** — large textures, uncompressed audio, leaked Addressables

### Step 3: Code Scan
Run `./scripts/validate-code-quality.sh` to find:
- GetComponent in Update
- Uncached Camera.main
- LINQ in gameplay code
- Allocations in hot paths

### Step 4: Fix
Apply targeted fixes based on profiling data.

### Step 5: Verify
Re-profile to confirm improvement. Compare before/after metrics.

## Performance Budgets

Starting points, not laws — tune against your actual target. Min-spec is the column that decides
whether someone can play at all, so budget for it first and let the high end scale up via quality
settings. See the `unity-optimizer` agent for the full table.

| Metric | Min-spec PC | Console (60fps mode) | High-end PC |
|--------|-------------|----------------------|-------------|
| Draw calls | < 1500 | < 3000 | < 5000 |
| Frame time | 16.6ms (60fps @ 1080p low) | 16.6ms (60fps) | 8.3ms (120fps) |
| VRAM | < 2GB | fixed — tune to the box | < 8GB |
| GC alloc/frame | 0 bytes | 0 bytes | 0 bytes |
