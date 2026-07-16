#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# generate-claude-md.sh
# Auto-generates a CLAUDE.md file by scanning a Unity project structure.
# Detects Unity version, render pipeline, installed packages, assembly
# definitions, and scene list to produce a comprehensive project context file.
#
# Usage: ./scripts/generate-claude-md.sh [project-dir]
#        Defaults to the current directory if no project-dir is given.
# =============================================================================

# ---------------------------------------------------------------------------
# Color support
# ---------------------------------------------------------------------------
if [[ -t 1 ]] && command -v tput &>/dev/null && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
    RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3)
    CYAN=$(tput setaf 6); BOLD=$(tput bold); RESET=$(tput sgr0)
else
    RED=""; GREEN=""; YELLOW=""; CYAN=""; BOLD=""; RESET=""
fi

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<EOF
${BOLD}generate-claude-md.sh${RESET} - Auto-generate a CLAUDE.md for a Unity project.

${BOLD}Usage:${RESET}
  ./scripts/generate-claude-md.sh [project-dir]

${BOLD}Arguments:${RESET}
  project-dir   Path to the Unity project root (defaults to current directory).

${BOLD}Description:${RESET}
  Scans ProjectSettings, Packages/manifest.json, .asmdef files, and
  EditorBuildSettings to produce a CLAUDE.md template with project context.
EOF
    exit 0
fi

# ---------------------------------------------------------------------------
# Resolve project directory
# ---------------------------------------------------------------------------
PROJECT_DIR="${1:-.}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

info()  { echo "${CYAN}[INFO]${RESET}  $*"; }
warn()  { echo "${YELLOW}[WARN]${RESET}  $*"; }
error() { echo "${RED}[ERROR]${RESET} $*"; }

# Basic sanity check
if [[ ! -d "$PROJECT_DIR/Assets" ]]; then
    error "No Assets/ directory found in $PROJECT_DIR. Is this a Unity project?"
    exit 1
fi

# ---------------------------------------------------------------------------
# 1. Unity version
# ---------------------------------------------------------------------------
UNITY_VERSION="unknown"
VERSION_FILE="$PROJECT_DIR/ProjectSettings/ProjectVersion.txt"
if [[ -f "$VERSION_FILE" ]]; then
    UNITY_VERSION=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+[a-zA-Z0-9]*' "$VERSION_FILE" | head -1)
    info "Unity version: $UNITY_VERSION"
else
    warn "ProjectVersion.txt not found."
fi

# ---------------------------------------------------------------------------
# 2. Render pipeline
# ---------------------------------------------------------------------------
RENDER_PIPELINE="Built-in (default)"
MANIFEST="$PROJECT_DIR/Packages/manifest.json"
if [[ -f "$MANIFEST" ]]; then
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
# ---------------------------------------------------------------------------
declare -A KNOWN_PACKAGES=(
    ["com.demigiant.dotween"]="DOTween"
    ["com.cysharp.unitask"]="UniTask"
    ["jp.hadashikick.vcontainer"]="VContainer"
    ["com.svermeulen.extenject"]="Zenject / Extenject"
    ["com.unity.inputsystem"]="Input System"
    ["com.unity.addressables"]="Addressables"
    ["com.unity.cinemachine"]="Cinemachine"
    ["com.unity.textmeshpro"]="TextMeshPro"
    ["com.unity.netcode.gameobjects"]="Netcode for GameObjects"
    ["com.unity.multiplayer.tools"]="Multiplayer Tools"
    ["com.unity.2d.animation"]="2D Animation"
    ["com.unity.2d.sprite"]="2D Sprite"
    ["com.unity.probuilder"]="ProBuilder"
    ["com.unity.recorder"]="Recorder"
    ["com.unity.ai.navigation"]="AI Navigation"
    ["com.unity.entities"]="Entities (DOTS)"
    ["com.unity.burst"]="Burst Compiler"
    ["com.unity.collections"]="Collections"
    ["com.unity.mathematics"]="Mathematics"
    ["com.unity.rendering.hybrid"]="Hybrid Renderer"
    ["com.unity.visualscripting"]="Visual Scripting"
    ["com.unity.localization"]="Localization"
)

DETECTED_PACKAGES=()
SKILLS_HINTS=()
if [[ -f "$MANIFEST" ]]; then
    for pkg_id in "${!KNOWN_PACKAGES[@]}"; do
        if grep -q "\"$pkg_id\"" "$MANIFEST"; then
            DETECTED_PACKAGES+=("${KNOWN_PACKAGES[$pkg_id]}")
        fi
    done
fi

if (( ${#DETECTED_PACKAGES[@]} > 0 )); then
    info "Detected packages: ${DETECTED_PACKAGES[*]}"
else
    info "No notable third-party/optional packages detected."
fi

# ---------------------------------------------------------------------------
# 4. Assembly definitions
# ---------------------------------------------------------------------------
ASMDEF_LIST=()
while IFS= read -r -d '' asmdef; do
    name=$(grep -oP '"name"\s*:\s*"\K[^"]+' "$asmdef" 2>/dev/null || basename "$asmdef" .asmdef)
    rel_path="${asmdef#"$PROJECT_DIR/"}"
    ASMDEF_LIST+=("$name ($rel_path)")
done < <(find "$PROJECT_DIR/Assets" -name '*.asmdef' -print0 2>/dev/null || true)

info "Found ${#ASMDEF_LIST[@]} assembly definition(s)."

# ---------------------------------------------------------------------------
# 5. Scene list
# ---------------------------------------------------------------------------
SCENE_LIST=()
BUILD_SETTINGS="$PROJECT_DIR/ProjectSettings/EditorBuildSettings.asset"
if [[ -f "$BUILD_SETTINGS" ]]; then
    while IFS= read -r line; do
        scene=$(echo "$line" | sed 's/.*path: //')
        SCENE_LIST+=("$scene")
    done < <(grep 'path:' "$BUILD_SETTINGS" || true)
fi
info "Found ${#SCENE_LIST[@]} scene(s) in build settings."

# ---------------------------------------------------------------------------
# 6. Determine skills to suggest
# ---------------------------------------------------------------------------
suggest_skills() {
    local skills=("unity-general")
    for pkg in "${DETECTED_PACKAGES[@]}"; do
        case "$pkg" in
            "Input System")       skills+=("unity-input-system") ;;
            "Addressables")       skills+=("unity-addressables") ;;
            "UniTask")            skills+=("unity-async") ;;
            "DOTween")            skills+=("unity-animation") ;;
            "Cinemachine")        skills+=("unity-cinemachine") ;;
            "Netcode for GameObjects") skills+=("unity-netcode") ;;
            "Entities (DOTS)")    skills+=("unity-dots") ;;
            "VContainer"|"Zenject / Extenject") skills+=("unity-di") ;;
        esac
    done
    echo "${skills[@]}"
}

SUGGESTED_SKILLS=$(suggest_skills)

# ---------------------------------------------------------------------------
# 7. Generate CLAUDE.md
# ---------------------------------------------------------------------------
OUTPUT="$PROJECT_DIR/CLAUDE.md"

cat > "$OUTPUT" <<MDEOF
# CLAUDE.md - Project Context for AI Assistants

> Auto-generated by \`generate-claude-md.sh\` on $(date +%Y-%m-%d).
> Review and customise this file to match your project's specifics.

---

## Project Overview

| Property         | Value |
|------------------|-------|
| **Unity Version** | $UNITY_VERSION |
| **Render Pipeline** | $RENDER_PIPELINE |
| **Project Root**  | \`$PROJECT_DIR\` |

### Detected Packages

MDEOF

if (( ${#DETECTED_PACKAGES[@]} > 0 )); then
    for pkg in "${DETECTED_PACKAGES[@]}"; do
        echo "- $pkg" >> "$OUTPUT"
    done
else
    echo "_No notable optional packages detected._" >> "$OUTPUT"
fi

cat >> "$OUTPUT" <<'MDEOF'

---

## Architecture

### Assembly Definitions

MDEOF

if (( ${#ASMDEF_LIST[@]} > 0 )); then
    for entry in "${ASMDEF_LIST[@]}"; do
        echo "- \`$entry\`" >> "$OUTPUT"
    done
else
    echo "_No .asmdef files found. Consider adding assembly definitions for faster compilation._" >> "$OUTPUT"
fi

cat >> "$OUTPUT" <<'MDEOF'

### Scenes in Build

MDEOF

if (( ${#SCENE_LIST[@]} > 0 )); then
    idx=0
    for scene in "${SCENE_LIST[@]}"; do
        echo "$idx. \`$scene\`" >> "$OUTPUT"
        ((idx++))
    done
else
    echo "_No scenes found in EditorBuildSettings._" >> "$OUTPUT"
fi

cat >> "$OUTPUT" <<MDEOF

---

## Build Targets

<!-- Adjust to match your actual targets -->
- **Primary:** PC / Mac Standalone
- **Secondary:** Android / iOS
- **CI:** _describe your CI setup here_

---

## Conventions

- Follow the coding standards defined in the rules files under \`.claude/rules/\`.
- Use PascalCase for public members, camelCase (with underscore prefix) for private fields.
- Prefer \`CompareTag()\` over \`== "tag"\`.
- Cache component references in \`Awake()\`/\`Start()\`; never call \`GetComponent\` in hot loops.
- Use assembly definitions to keep compilation fast.
- All serialised assets must use Unity YAML (Force Text) serialisation.

---

## Skills to Load

Based on detected packages, consider loading these Claude skill/context files:

$(for s in $SUGGESTED_SKILLS; do echo "- \`$s\`"; done)

---

## Custom Notes

<!-- Add any project-specific notes, gotchas, or context for AI assistants here. -->

MDEOF

echo ""
echo "${GREEN}${BOLD}CLAUDE.md generated successfully at:${RESET} $OUTPUT"
echo "${CYAN}Review the file and fill in project-specific sections.${RESET}"
