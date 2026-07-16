---
name: unity-network
description: "Set up multiplayer networking — writes network scripts, configures NetworkManager via MCP. Supports Netcode, Mirror, Photon, Fish-Net."
user-invocable: true
args: framework_and_feature
---

# /unity-network — Set Up Multiplayer

Implement networking based on: **$ARGUMENTS**

## Workflow

Use the `unity-network-dev` agent to:

1. **Detect framework** — check `Packages/manifest.json` for Netcode/Mirror/Photon/Fish-Net
2. **Plan the feature** — identify what needs to sync (transform, state, RPCs)
3. **Write networking scripts:**
   - NetworkBehaviour components
   - NetworkVariable for synced state
   - ServerRpc/ClientRpc for actions
   - Ownership checks (`if (!IsOwner) return`)
4. **Set up scene** via MCP:
   - NetworkManager GameObject
   - Transport configuration
   - Player spawn points
   - Network prefab registration
5. **Verify** via `read_console`

## Key Rules
- Server is authoritative — never trust client
- Minimize RPCs — use NetworkVariables for continuous state
- Always check ownership before processing input
- Register all network prefabs with NetworkManager
