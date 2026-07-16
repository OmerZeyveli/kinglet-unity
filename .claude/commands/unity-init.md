---
name: unity-init
description: "Scans a Unity project and generates a tailored CLAUDE.md with detected configuration, packages, render pipeline, and recommended skills."
user-invocable: true
---

# /unity-init — Project Setup

Scan this Unity project and generate a tailored CLAUDE.md configuration.

## Steps

1. **Read project info** via MCP `project_info` resource to get Unity version, platform, and state.

2. **Scan Packages/manifest.json** to detect installed packages:
   - Render pipeline (URP, HDRP, or Built-in)
   - Input System, Addressables, Cinemachine, Timeline, TextMeshPro
   - Networking (Netcode, Mirror, Photon, Fish-Net)
   - Third-party (DOTween, UniTask, VContainer, Zenject, Odin)

3. **Scan for assembly definitions** (`.asmdef` files) — map the project's assembly structure.

4. **Scan for scenes** — list all `.unity` files in `Assets/`.

5. **Check existing CLAUDE.md** — if one exists, preserve user customizations.

6. **Generate CLAUDE.md** with:
   - Project overview (Unity version, render pipeline, detected packages)
   - Assembly structure
   - Scene list
   - References to rules files (`.claude/rules/*.md`)
   - Recommended skills based on detected packages
   - MCP integration notes
   - Key conventions summary

7. **Report** what was detected and configured. Suggest next steps:
   - Review and customize the generated CLAUDE.md
   - Install unity-mcp if not already present
   - Try `/unity-audit` for a full project health check

## Output

Present the results in a clear summary table showing what was detected and which skills are recommended.
