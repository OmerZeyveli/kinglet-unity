---
name: unity-profile
description: "Deep profiling session — captures frames via MCP, analyzes CPU/GPU timing, memory snapshots, rendering stats, and provides optimization recommendations."
user-invocable: true
args: focus
---

# /unity-profile — Deep Profiling Session

Run a deep profiling session. Focus: **$ARGUMENTS**

## Workflow

Use the `unity-optimizer` agent to:

### Step 1: Capture
```
manage_profiler action:"start_session"     → begin recording
manage_profiler action:"get_frame_timing"  → CPU and GPU frame times
manage_profiler action:"get_counters"      → specific perf counters
manage_profiler action:"memory_snapshot"   → detailed memory breakdown
manage_graphics action:"get_rendering_stats" → draw calls, batches, triangles, set passes
manage_physics  action:"get_stats"         → physics step time, contacts, bodies
```

### Step 2: Analyze

Present a profile report:

**Frame Timing:**
- CPU frame time: Xms (target: <16.6ms for 60fps)
- GPU frame time: Xms
- Bottleneck: CPU / GPU / balanced

**Rendering:**
- Draw calls: X (budget: <100 mobile, <2000 desktop)
- Batches: X (SRP Batcher efficiency)
- Triangles: X
- Set pass calls: X

**Memory:**
- Total: X MB
- Textures: X MB
- Meshes: X MB
- Audio: X MB
- Scripts: X MB

**Physics:**
- Physics step time: X ms
- Active rigidbodies: X
- Contacts: X

### Step 3: Recommend

Provide specific, actionable optimization recommendations ranked by impact:
1. Highest impact fix
2. Second highest
3. ...

Each recommendation includes: what to change, why, expected improvement.
