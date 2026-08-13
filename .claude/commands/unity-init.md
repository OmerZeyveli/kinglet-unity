---
name: unity-init
description: "Use once per project, right after Kinglet is installed — when `CLAUDE.md` still has unfilled `FILL:` markers, or when the user asks to set up or initialise the toolkit for this Unity project."
user-invocable: true
---

# /unity-init — Project Setup

> **Architecture stack — read before you write or refuse.** Which parts of
> `.claude/rules/architecture.md` bind here is stated in `CLAUDE.md`'s generated block, detected
> from this project's own code rather than assumed. A project with no VContainer is **not** a
> project where this surface does not apply — it is a project where you follow the architecture
> the code actually has. Refusing on stack grounds without reading that block is how a measured
> session locked itself out of every MCP-driven agent it had.

Scan this Unity project and generate a tailored CLAUDE.md configuration.

## Steps

1. **Read project info** via MCP `project_info` resource to get Unity version, platform, and state.

2. **Scan Packages/manifest.json** to detect installed packages:
   - Render pipeline — **four** states, not three: URP, HDRP, Built-in, or *both packages present*.
     `.claude/scripts/detect-pipeline.sh` is the one detector and reports that fourth state as its
     own rather than picking a winner. Report it the same way; do not resolve it to one pipeline.
     Package presence is evidence, not the active pipeline — Unity records that in
     `ProjectSettings/GraphicsSettings.asset`, which nothing in this toolkit reads.
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
   - Try `/unity-doctor` for a full project health check

## Output

Present the results in a clear summary table showing what was detected and which skills are recommended.

## Suggest next

When this command finishes, name the next step and offer it. Do not take it.

Offer `/unity-doctor` to confirm the install, and name the `FILL:` markers still unfilled in `CLAUDE.md`.
