---
name: unity-prototype
description: "The killer feature. One prompt to playable prototype — writes scripts, builds scene via MCP, sets up physics/camera, wires everything together."
user-invocable: true
args: mechanic_description
---

# /unity-prototype — Rapid Prototype

Create a playable prototype of: **$ARGUMENTS**

## Workflow

Use the `unity-prototyper` agent to deliver a complete, playable prototype.

### Step 1: Decompose
Break the mechanic into:
- Player systems (movement, abilities, input)
- World elements (platforms, obstacles, triggers)
- Game rules (win/lose, scoring)
- Camera behavior

### Step 2: Write Scripts
Create minimal, functional C# scripts:
- Player controller with exposed `[SerializeField]` parameters
- Game mechanics (physics, triggers, scoring)
- Follow the prototype design principle: **functional > clean**

### Step 3: Build Scene via MCP
Using `batch_execute` for speed:
1. Create a new scene named `Prototype_[MechanicName]`
2. Create all GameObjects (player, environment, obstacles, camera)
3. Add and configure components (Rigidbody, Collider, Renderer)
4. Set up physics layers and collision matrix
5. Configure Cinemachine camera to follow player

### Step 4: Verify
- Check console via `read_console` for any errors
- Report the complete prototype setup to the user

### Step 5: Report
Tell the user:
- **Controls** — what keys/buttons to use
- **Scripts created** — file names and locations
- **Scene** — name and how to open it
- **Tweakable values** — which SerializeField parameters to adjust
- **Next steps** — what to add for a fuller prototype

## Step 6: Auto-Verify (Optional)

After the prototype is complete, offer to run the `unity-verifier` agent:
- Quick review of all prototype scripts for critical issues
- Auto-fix serialization safety, null checks, and performance pitfalls
- Skip architecture concerns (prototypes prioritize speed over structure)

Suggest: "Prototype ready! Want me to run a quick verification pass?"

## Design Rules
- 10-minute target — if it takes longer, you're overbuilding
- Placeholder visuals — colored primitives, no art needed
- Everything tweakable — SerializeField with Headers
- Single scene — no multi-scene for prototypes
- No UI — use Debug.Log and Gizmos for feedback
