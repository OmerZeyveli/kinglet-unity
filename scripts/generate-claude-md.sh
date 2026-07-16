#!/usr/bin/env bash
# =============================================================================
# generate-claude-md.sh
# Emits a CLAUDE.md for a Unity project by scanning it, combining a
# human-authored vision half (FILL: markers) with auto-detected project facts.
#
# Usage:
#   ./scripts/generate-claude-md.sh [--facts-only] [project-dir]   > CLAUDE.md
#
#   --facts-only   Emit ONLY the auto-generated facts block (the content that
#                  lives between the generated:begin/end markers). Used to
#                  refresh an existing CLAUDE.md without touching prose.
#
# CONTRACT: the document goes to STDOUT. Every log line goes to STDERR. The
# caller owns the destination file.
#
# This matters. Upstream (everything-claude-unity v1.5.0) had this script write
# $PROJECT_DIR/CLAUDE.md itself while ALSO logging to stdout, and install.sh
# called it as `generate-claude-md.sh "$dir" > "$CLAUDE_MD"`. Two writers, one
# file, independent offsets: on a fresh install the trailing status line landed
# mid-document and punched out the Unity Version / Render Pipeline rows; when a
# CLAUDE.md already existed, install.sh redirected to CLAUDE.md.generated to
# protect it, but the script overwrote the real CLAUDE.md regardless — the
# guard destroyed the file it was meant to save. stdout-only is the fix.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors — stderr only, so they never contaminate the document
# ---------------------------------------------------------------------------
if [ -t 2 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    RED=$(tput setaf 1); YELLOW=$(tput setaf 3); CYAN=$(tput setaf 6); RESET=$(tput sgr0)
else
    RED=""; YELLOW=""; CYAN=""; RESET=""
fi
info()  { echo "${CYAN}[INFO]${RESET}  $*" >&2; }
warn()  { echo "${YELLOW}[WARN]${RESET}  $*" >&2; }
error() { echo "${RED}[ERROR]${RESET} $*" >&2; }

usage() { sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
FACTS_ONLY=0
PROJECT_DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --facts-only) FACTS_ONLY=1; shift ;;
        -h|--help)    usage ;;
        -*)           error "Unknown option: $1"; exit 2 ;;
        *)            PROJECT_DIR="$1"; shift ;;
    esac
done
PROJECT_DIR="${PROJECT_DIR:-.}"
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || { error "Directory not found: $PROJECT_DIR"; exit 1; }

if [ ! -d "$PROJECT_DIR/Assets" ]; then
    error "No Assets/ directory found in $PROJECT_DIR. Is this a Unity project?"
    exit 1
fi

MANIFEST="$PROJECT_DIR/Packages/manifest.json"

# ---------------------------------------------------------------------------
# 1. Unity version
# ---------------------------------------------------------------------------
UNITY_VERSION="unknown"
VERSION_FILE="$PROJECT_DIR/ProjectSettings/ProjectVersion.txt"
if [ -f "$VERSION_FILE" ]; then
    UNITY_VERSION=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+[a-zA-Z0-9]*' "$VERSION_FILE" | head -1)
    info "Unity version: $UNITY_VERSION"
else
    warn "ProjectVersion.txt not found."
fi

# ---------------------------------------------------------------------------
# 2. Render pipeline
# ---------------------------------------------------------------------------
RENDER_PIPELINE="Built-in (default)"
if [ -f "$MANIFEST" ]; then
    if grep -q 'com.unity.render-pipelines.universal' "$MANIFEST"; then
        RENDER_PIPELINE="Universal Render Pipeline (URP)"
    elif grep -q 'com.unity.render-pipelines.high-definition' "$MANIFEST"; then
        RENDER_PIPELINE="High Definition Render Pipeline (HDRP)"
    fi
    info "Render pipeline: $RENDER_PIPELINE"
else
    warn "Packages/manifest.json not found."
fi

# ---------------------------------------------------------------------------
# 3. Detect installed packages
#
# A newline-separated "id<TAB>label" table rather than `declare -A`: associative
# arrays need bash 4, and macOS still ships bash 3.2. .gitattributes says we
# target macOS, so this has to work there.
# ---------------------------------------------------------------------------
KNOWN_PACKAGES=$(cat <<'PKGS'
com.demigiant.dotween	DOTween
com.cysharp.unitask	UniTask
jp.hadashikick.vcontainer	VContainer
com.svermeulen.extenject	Zenject / Extenject
com.unity.inputsystem	Input System
com.unity.addressables	Addressables
com.unity.cinemachine	Cinemachine
com.unity.textmeshpro	TextMeshPro
com.unity.netcode.gameobjects	Netcode for GameObjects
com.unity.multiplayer.tools	Multiplayer Tools
com.unity.2d.animation	2D Animation
com.unity.2d.sprite	2D Sprite
com.unity.probuilder	ProBuilder
com.unity.recorder	Recorder
com.unity.ai.navigation	AI Navigation
com.unity.entities	Entities (DOTS)
com.unity.burst	Burst Compiler
com.unity.collections	Collections
com.unity.mathematics	Mathematics
com.unity.rendering.hybrid	Hybrid Renderer
com.unity.visualscripting	Visual Scripting
com.unity.localization	Localization
PKGS
)

DETECTED_PACKAGES=""   # newline-separated labels
if [ -f "$MANIFEST" ]; then
    while IFS=$'\t' read -r pkg_id label; do
        [ -n "$pkg_id" ] || continue
        if grep -q "\"$pkg_id\"" "$MANIFEST"; then
            DETECTED_PACKAGES="${DETECTED_PACKAGES}${label}"$'\n'
        fi
    done <<< "$KNOWN_PACKAGES"
fi
PKG_COUNT=$(printf '%s' "$DETECTED_PACKAGES" | grep -c . || true)
info "Detected $PKG_COUNT package(s) of interest."

# ---------------------------------------------------------------------------
# 4. Assembly definitions
#
# sed, not `grep -oP` — PCRE mode is a GNU extension and BSD/macOS grep has no
# -P at all.
# ---------------------------------------------------------------------------
ASMDEF_LIST=""
while IFS= read -r asmdef; do
    [ -n "$asmdef" ] || continue
    name=$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$asmdef" 2>/dev/null | head -1)
    [ -n "$name" ] || name=$(basename "$asmdef" .asmdef)
    rel_path="${asmdef#"$PROJECT_DIR"/}"
    ASMDEF_LIST="${ASMDEF_LIST}${name} (${rel_path})"$'\n'
done < <(find "$PROJECT_DIR/Assets" -name '*.asmdef' 2>/dev/null || true)
ASMDEF_COUNT=$(printf '%s' "$ASMDEF_LIST" | grep -c . || true)
info "Found $ASMDEF_COUNT assembly definition(s)."

# ---------------------------------------------------------------------------
# 5. Scene list
# ---------------------------------------------------------------------------
SCENE_LIST=""
BUILD_SETTINGS="$PROJECT_DIR/ProjectSettings/EditorBuildSettings.asset"
if [ -f "$BUILD_SETTINGS" ]; then
    while IFS= read -r line; do
        scene=$(printf '%s' "$line" | sed 's/.*path: //')
        [ -n "$scene" ] && SCENE_LIST="${SCENE_LIST}${scene}"$'\n'
    done < <(grep 'path:' "$BUILD_SETTINGS" 2>/dev/null || true)
fi
SCENE_COUNT=$(printf '%s' "$SCENE_LIST" | grep -c . || true)
info "Found $SCENE_COUNT scene(s) in build settings."

# ---------------------------------------------------------------------------
# 6. Skills worth loading, by real catalog path
#
# Upstream suggested names like `unity-input-system` and `unity-general` that
# match nothing in .claude/skills/ — the paths below are the real ones.
# ---------------------------------------------------------------------------
suggest_skills() {
    local out=""
    while IFS= read -r pkg; do
        [ -n "$pkg" ] || continue
        case "$pkg" in
            "Input System")            out="${out}systems/input-system"$'\n' ;;
            "Addressables")            out="${out}systems/addressables"$'\n' ;;
            "UniTask")                 out="${out}third-party/unitask"$'\n' ;;
            "DOTween")                 out="${out}third-party/dotween"$'\n' ;;
            "TextMeshPro")             out="${out}third-party/textmeshpro"$'\n' ;;
            "Cinemachine")             out="${out}systems/cinemachine"$'\n' ;;
            "AI Navigation")           out="${out}systems/navmesh"$'\n' ;;
            "VContainer")              out="${out}third-party/vcontainer"$'\n' ;;
        esac
    done <<< "$DETECTED_PACKAGES"
    case "$RENDER_PIPELINE" in
        *URP*) out="${out}systems/urp-pipeline"$'\n' ;;
    esac
    printf '%s' "$out" | sort -u
}
SUGGESTED_SKILLS=$(suggest_skills)

# ---------------------------------------------------------------------------
# 7. Emit — everything below goes to STDOUT
# ---------------------------------------------------------------------------

emit_facts() {
    cat <<MDEOF
| Property | Value |
|----------|-------|
| **Unity Version** | $UNITY_VERSION |
| **Render Pipeline** | $RENDER_PIPELINE |
| **Assembly Definitions** | $ASMDEF_COUNT |
| **Scenes in Build Settings** | $SCENE_COUNT |

**Detected packages**
MDEOF

    if [ "$PKG_COUNT" -gt 0 ]; then
        printf '%s' "$DETECTED_PACKAGES" | while IFS= read -r p; do [ -n "$p" ] && echo "- $p"; done
    else
        echo "_No notable optional packages detected._"
    fi

    echo ""
    echo "**Assembly definitions**"
    echo ""
    if [ "$ASMDEF_COUNT" -gt 0 ]; then
        printf '%s' "$ASMDEF_LIST" | while IFS= read -r a; do [ -n "$a" ] && echo "- \`$a\`"; done
    else
        echo "_None found. Consider adding assembly definitions to keep compile times down._"
    fi

    echo ""
    echo "**Scenes in build settings**"
    echo ""
    if [ "$SCENE_COUNT" -gt 0 ]; then
        idx=1
        printf '%s' "$SCENE_LIST" | while IFS= read -r s; do
            [ -n "$s" ] && { echo "$idx. \`$s\`"; idx=$((idx + 1)); }
        done
    else
        echo "_No scenes found in EditorBuildSettings._"
    fi

    if [ -n "$SUGGESTED_SKILLS" ]; then
        echo ""
        echo "**Skills matching this project**"
        echo ""
        printf '%s\n' "$SUGGESTED_SKILLS" | while IFS= read -r s; do [ -n "$s" ] && echo "- \`.claude/skills/$s/\`"; done
    fi
}

if [ "$FACTS_ONLY" -eq 1 ]; then
    emit_facts
    info "Emitted facts block only."
    exit 0
fi

cat <<'MDEOF'
# [FILL: Game Title] — Project Guide

> Unity 6 · C# · PC / Console · built with cloud-nine-unity.

## Vision

<!-- This half is yours. The generator never overwrites it — see the marked region below. -->

- **Elevator pitch:** <!-- FILL: "It's a [genre] where you [core action] in a [setting] to [goal]." -->
- **Core fantasy:** <!-- FILL: the emotional promise — what the player gets to be/do here -->
- **Unique hook:** <!-- FILL: passes the "and also" test -->
- **Genre / subgenre:** <!-- FILL -->
- **Target platforms:** <!-- FILL: PC (Steam/Epic) / Console / both — NO mobile -->
- **Primary input:** <!-- FILL: keyboard+mouse and/or gamepad (with rebinding) -->

## Pillars

<!-- FILL: 3–5 pillars, each with a design test that can settle an argument -->

## Scope

- **Estimated scope / team size:** <!-- FILL: e.g. Medium (3–9 months), solo -->
- **MVP hypothesis:** <!-- FILL: the single question the MVP answers — "is the core loop fun?" -->
- **Current milestone:** <!-- FILL -->

---

MDEOF

echo "<!-- cloud-nine-unity:generated:begin — content between these markers is rewritten on re-install. Everything outside is yours. -->"
echo ""
echo "## Project Facts (auto-detected)"
echo ""
emit_facts
echo ""
echo "<!-- cloud-nine-unity:generated:end -->"

cat <<'MDEOF'

---

## Engineering Stance (fixed — do not casually change)

- **Engine / language:** Unity 6, C#.
- **Architecture:** Model-View-System (MVS) with **VContainer** (DI), **MessagePipe** (cross-system
  messaging — no singletons or static event buses), **UniTask** (async — no coroutines), and the
  **New Input System** (legacy `Input.*` is blocked by a hook).
- **Platform:** PC / console. No mobile code, touch input, or mobile performance budgets.
- **Rules** live in `.claude/rules/` and are binding:
  - `architecture.md` · `csharp-unity.md` · `performance.md` · `serialization.md` ·
    `unity-specifics.md` — the spine.
  - `pc-console.md` — the platform spec. It adds specifics on top of the spine; on any apparent
    conflict the spine wins.

## Where things go

- **Design docs** (GDDs, concept, systems index): `docs/design/`
- **Architecture decisions** (ADRs): `docs/adr/`
- **Production** (sprints, milestones, retrospectives): `docs/production/`
- **Game code:** `Assets/Scripts/`. Tuning data lives in ScriptableObjects / external config —
  never hardcoded.

## How to work

- **Design & production** (documentation layer — no editor/code):
  `/brainstorm` → `/map-systems` → `/design-system` → `/design-review`; plan with `/sprint-plan`,
  `/estimate`, `/scope-check`, `/milestone-review`, `/retrospective`. Agents: `game-designer`,
  `systems-designer`, `level-designer`, `creative-director`, `technical-director` (+ optional
  `narrative-director`, `writer`, `world-builder`).
- **Implementation** (drives the Unity Editor via MCP): `/unity-feature`, `/unity-prototype`,
  `/unity-scene`, `/unity-test`, `/unity-review`, and the rest of the `/unity-*` commands.
- **MCP:** the CoplayDev Unity MCP bridge must be running for editor control — see `MCP-SETUP.md`.
  Verify with "What's in the current scene?"

## Conventions reminder (see `.claude/rules/`)

- `[SerializeField] private` for inspector fields; `_lowerCamelCase` privates; `== null` (never `?.`
  / `is null`) on Unity objects; `[FormerlySerializedAs]` on every renamed serialized field; zero GC
  allocations in `Update`/`FixedUpdate`/`LateUpdate`; cache `GetComponent` / `Camera.main`.

## Custom Notes

<!-- Anything project-specific: gotchas, conventions, context for future sessions. -->
MDEOF

info "CLAUDE.md emitted to stdout."
