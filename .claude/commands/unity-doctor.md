---
name: unity-doctor
description: "Diagnostic health check — verifies MCP connectivity, .claude/ integrity, Unity project structure, and hook registration."
user-invocable: true
---

# /unity-doctor — Diagnostic Health Check

Run a comprehensive diagnostic check on the everything-claude-unity installation and the Unity project. Report each check as **PASS**, **WARNING**, or **ERROR** with actionable fixes.

## Check 1: Unity MCP Server Connectivity

1. Attempt to call `project_info` via MCP to get Unity version and project state.
2. If it succeeds: report Unity version, platform, and play mode state → **PASS**
3. If it fails: report the error → **ERROR** with suggestions:
   - Is the unity-mcp package installed in Unity?
   - Is the Unity Editor running and the project open?
   - Is the MCP server running on the expected port?
   - Check `.claude/settings.json` → `mcpServers.unityMCP.url`

## Check 2: .claude/ Directory Integrity

1. Verify expected directories exist: `commands/`, `agents/`, `hooks/`, `skills/`, `rules/`
2. For each hook in `hooks/`: check the file exists and is executable (`-x` permission)
3. For each command in `commands/`: verify it has YAML frontmatter with `name` and `description`
4. For each agent in `agents/`: verify it has YAML frontmatter with `name`, `description`, `model`, and `tools`
5. Check `.claude/VERSION` file exists and report version number
6. Report counts: X commands, Y agents, Z hooks, W skills, V rules
7. Any missing directories → **ERROR**; any invalid frontmatter → **WARNING**; all good → **PASS**

## Check 3: Hook Registration Completeness

1. Read `.claude/settings.json`
2. For every `.sh` file in `hooks/` directory (excluding `_lib.sh`):
   - Check it is registered in either `PreToolUse` or `PostToolUse` in settings.json
   - Report unregistered hooks → **WARNING**
3. For every hook path in settings.json:
   - Check the referenced file exists
   - Report missing files → **ERROR**
4. Verify blocking hooks (`block-*.sh`) are in `PreToolUse` and warning hooks (`warn-*.sh`, `validate-*.sh`, `suggest-*.sh`) are in `PostToolUse`
5. All correct → **PASS**

## Check 4: Unity Project Structure

1. Check for `Assets/` directory → **ERROR** if missing
2. Check for `ProjectSettings/` directory → **ERROR** if missing
3. Check for `Packages/manifest.json` → **WARNING** if missing
4. Check for `CLAUDE.md` in project root → **WARNING** if missing, suggest `/unity-init`
5. Search for `.asmdef` files in `Assets/` → **WARNING** if none found
6. Search for test assembly definitions (`*Tests*.asmdef`) → **WARNING** if none, suggest `/unity-test`
7. All present → **PASS**

## Check 5: Skill/Package Alignment

1. Read `Packages/manifest.json` to detect installed Unity packages
2. Cross-reference with available skills in `.claude/skills/`:

| Package | Expected Skill |
|---------|---------------|
| `com.unity.inputsystem` | `systems/input-system` |
| `com.unity.addressables` | `systems/addressables` |
| `com.unity.cinemachine` | `systems/cinemachine` |
| `com.unity.render-pipelines.universal` | `systems/urp-pipeline` |
| `com.unity.textmeshpro` | `third-party/textmeshpro` |
| `com.unity.timeline` | — (no skill yet) |

3. Also check for third-party packages in `Assets/`:
   - `DOTween` → `third-party/dotween`
   - `UniTask` → `third-party/unitask`
   - `VContainer` → `third-party/vcontainer`
   - `Odin` → `third-party/odin-inspector`

4. Report packages without matching skills → **WARNING** (capability gap)
5. All aligned → **PASS**

## Output Format

Present a summary report:

```
=== Unity Doctor Report ===

MCP Server:        PASS  (Unity 2022.3.20f1, StandaloneWindows64)
.claude/ Integrity: PASS  (17 commands, 14 agents, 9 hooks, 35 skills, 5 rules)
Hook Registration:  PASS  (all hooks registered correctly)
Project Structure:  WARNING — no test assembly definitions found
Skill Alignment:    WARNING — DOTween detected but no matching skill loaded

Overall: 2 warnings, 0 errors
```

For each WARNING or ERROR, include the actionable fix immediately after the line.
