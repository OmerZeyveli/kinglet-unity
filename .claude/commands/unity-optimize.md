---
name: unity-optimize
description: "Use when the user asks about performance — a specific complaint like stuttering or frame drops, or a general check of how the project is running. Profiles via MCP to find the real cause before changing anything, rather than fixing from a guess."
user-invocable: true
args: focus_area
---

# /unity-optimize — Performance Optimization

> **Architecture stack — read before you write or refuse.** Which parts of
> `.claude/rules/architecture.md` bind here is stated in `CLAUDE.md`'s generated block, detected
> from this project's own code rather than assumed. A project with no VContainer is **not** a
> project where this surface does not apply — it is a project where you follow the architecture
> the code actually has. Refusing on stack grounds without reading that block is how a measured
> session locked itself out of every MCP-driven agent it had.

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
Read the files the profiler named in Step 1 and look for:
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

## Suggest next

When this command finishes, name the next step and offer it. Do not take it.

Offer a second profile pass to confirm the gain is real, with before/after frames.
