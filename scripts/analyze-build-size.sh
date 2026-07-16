#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# analyze-build-size.sh
# Parses Unity Editor.log for build size information. Extracts the Build Report
# section, sorts assets by size, and flags common issues like oversized
# textures, uncompressed audio, and large meshes.
#
# Usage:
#   ./scripts/analyze-build-size.sh [--log <path>]
#   Without --log, searches for the most recent Editor.log in platform-specific
#   default locations.
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
${BOLD}analyze-build-size.sh${RESET} - Parse Unity Editor.log for build size info.

${BOLD}Usage:${RESET}
  ./scripts/analyze-build-size.sh [--log <path>]

${BOLD}Options:${RESET}
  --log <path>   Path to a specific Unity Editor.log file.
  --help         Show this help message.

${BOLD}Default log locations:${RESET}
  macOS:   ~/Library/Logs/Unity/Editor.log
  Linux:   ~/.config/unity3d/Editor.log
  Windows: %LOCALAPPDATA%/Unity/Editor/Editor.log

${BOLD}Output:${RESET}
  - Top 20 largest assets from the build report
  - Total build size
  - Flags for common issues (large textures, uncompressed audio, etc.)
EOF
    exit 0
fi

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
LOG_PATH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --log) LOG_PATH="$2"; shift 2 ;;
        *) echo "${RED}Unknown option: $1${RESET}"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Locate Editor.log
# ---------------------------------------------------------------------------
if [[ -z "$LOG_PATH" ]]; then
    case "$(uname -s)" in
        Darwin)
            LOG_PATH="$HOME/Library/Logs/Unity/Editor.log"
            ;;
        Linux)
            LOG_PATH="$HOME/.config/unity3d/Editor.log"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            if [[ -n "${LOCALAPPDATA:-}" ]]; then
                LOG_PATH="$LOCALAPPDATA/Unity/Editor/Editor.log"
            else
                LOG_PATH="$HOME/AppData/Local/Unity/Editor/Editor.log"
            fi
            ;;
        *)
            echo "${RED}[ERROR]${RESET} Unknown platform. Use --log <path> to specify the log file."
            exit 1
            ;;
    esac
fi

if [[ ! -f "$LOG_PATH" ]]; then
    echo "${RED}[ERROR]${RESET} Editor.log not found at: $LOG_PATH"
    echo "  Use ${CYAN}--log <path>${RESET} to specify the file location."
    echo "  Make sure you have built the project at least once in the Unity Editor."
    exit 1
fi

echo ""
echo "${BOLD}=== Unity Build Size Analysis ===${RESET}"
echo "  Log file: $LOG_PATH"
echo "  Log size: $(du -h "$LOG_PATH" | cut -f1)"
echo ""

# ---------------------------------------------------------------------------
# Extract Build Report section
# ---------------------------------------------------------------------------
# Unity's build report typically appears between lines like:
#   "Build Report" and the next major section or end of relevant data.
# The asset lines look like:
#   " 1.2 mb	 0.5% Assets/Textures/MyTexture.png"

BUILD_REPORT=""

# Try to find the LAST build report in the log (most recent build)
# The section starts with "Build Report" and contains lines with sizes
if grep -q "Build Report" "$LOG_PATH" 2>/dev/null; then
    # Get line number of the last "Build Report" occurrence
    last_report_line=$(grep -n "Build Report" "$LOG_PATH" | tail -1 | cut -d: -f1)

    if [[ -n "$last_report_line" ]]; then
        # Extract ~500 lines after the Build Report header
        BUILD_REPORT=$(tail -n +"$last_report_line" "$LOG_PATH" | head -n 500)
    fi
fi

if [[ -z "$BUILD_REPORT" ]]; then
    echo "${YELLOW}[WARN]${RESET} No Build Report section found in the log."
    echo "  Make sure you have performed a build in Unity. The Build Report"
    echo "  is written to Editor.log after each build completes."
    echo ""
    echo "  To generate a build report:"
    echo "  1. Open your project in Unity"
    echo "  2. Build (File > Build Settings > Build)"
    echo "  3. Re-run this script"
    exit 0
fi

# ---------------------------------------------------------------------------
# Parse asset lines
# ---------------------------------------------------------------------------
# Typical format:  " 2.1 mb	 3.2% Assets/Textures/hero.png"
# or:              " 456.7 kb	 0.1% Assets/Scripts/foo.cs"

echo "${BOLD}--- Top 20 Largest Assets ---${RESET}"
echo ""

# Extract lines that look like asset entries (size + percentage + path)
# Sort by size (converting to bytes for proper numeric sort)
declare -a ASSET_LINES=()
declare -a ASSET_SIZES_KB=()
declare -a ASSET_PATHS=()

parse_size_to_kb() {
    local size_str="$1"
    local unit="$2"
    local size_val
    size_val=$(echo "$size_str" | sed 's/[^0-9.]//g')

    case "$(echo "$unit" | tr '[:upper:]' '[:lower:]')" in
        gb) echo "$size_val * 1048576" | bc 2>/dev/null || echo "0" ;;
        mb) echo "$size_val * 1024" | bc 2>/dev/null || echo "0" ;;
        kb) echo "$size_val" | bc 2>/dev/null || echo "0" ;;
        b)  echo "scale=2; $size_val / 1024" | bc 2>/dev/null || echo "0" ;;
        *)  echo "0" ;;
    esac
}

# Parse the build report for asset lines
line_count=0
while IFS= read -r line; do
    # Match lines like: " 2.1 mb	 3.2% Assets/..."
    if [[ "$line" =~ ^[[:space:]]*([0-9]+\.?[0-9]*)[[:space:]]*(kb|mb|gb|b)[[:space:]]+([0-9]+\.?[0-9]*)%[[:space:]]+(.*) ]]; then
        size_num="${BASH_REMATCH[1]}"
        size_unit="${BASH_REMATCH[2]}"
        percentage="${BASH_REMATCH[3]}"
        asset_path="${BASH_REMATCH[4]}"

        size_kb=$(parse_size_to_kb "$size_num" "$size_unit")

        ASSET_LINES+=("$(printf '%012.2f|%s %s|%s%%|%s' "$size_kb" "$size_num" "$size_unit" "$percentage" "$asset_path")")
        ASSET_SIZES_KB+=("$size_kb")
        ASSET_PATHS+=("$asset_path")
        ((line_count++))
    fi
done <<< "$BUILD_REPORT"

if (( line_count == 0 )); then
    echo "  ${YELLOW}No asset size entries found in the Build Report.${RESET}"
    echo "  The log may use a different format. Check the log manually."
    echo ""
else
    # Sort by size (descending) and show top 20
    printf '%s\n' "${ASSET_LINES[@]}" | sort -t'|' -k1 -rn | head -20 | while IFS='|' read -r _sort_key size pct path; do
        # Color large items
        size_trimmed=$(echo "$size" | sed 's/^[[:space:]]*//')
        if echo "$size_trimmed" | grep -qi 'mb\|gb'; then
            size_val=$(echo "$size_trimmed" | grep -oE '[0-9]+\.?[0-9]*')
            if echo "$size_trimmed" | grep -qi 'gb' || (echo "$size_trimmed" | grep -qi 'mb' && (( $(echo "$size_val > 10" | bc 2>/dev/null || echo 0) ))); then
                printf "  ${RED}%-12s${RESET}  %-6s  %s\n" "$size_trimmed" "$pct" "$path"
            elif echo "$size_trimmed" | grep -qi 'mb' && (( $(echo "$size_val > 2" | bc 2>/dev/null || echo 0) )); then
                printf "  ${YELLOW}%-12s${RESET}  %-6s  %s\n" "$size_trimmed" "$pct" "$path"
            else
                printf "  %-12s  %-6s  %s\n" "$size_trimmed" "$pct" "$path"
            fi
        else
            printf "  %-12s  %-6s  %s\n" "$size_trimmed" "$pct" "$path"
        fi
    done
fi

echo ""

# ---------------------------------------------------------------------------
# Total build size
# ---------------------------------------------------------------------------
echo "${BOLD}--- Build Size Summary ---${RESET}"
echo ""

total_line=$(echo "$BUILD_REPORT" | grep -iE 'Total (compressed|uncompressed|build) size' | tail -1 || true)
if [[ -n "$total_line" ]]; then
    echo "  $total_line"
else
    # Try alternative format
    complete_size=$(echo "$BUILD_REPORT" | grep -iE 'Complete size|Complete build size' | tail -1 || true)
    if [[ -n "$complete_size" ]]; then
        echo "  $complete_size"
    else
        echo "  ${YELLOW}Could not extract total build size from the report.${RESET}"
    fi
fi

echo "  Total asset entries in report: $line_count"
echo ""

# ---------------------------------------------------------------------------
# Flag common issues
# ---------------------------------------------------------------------------
echo "${BOLD}--- Potential Issues ---${RESET}"
echo ""

issue_count=0

# Check for large textures (>2MB)
for i in "${!ASSET_PATHS[@]}"; do
    path="${ASSET_PATHS[$i]}"
    size_kb="${ASSET_SIZES_KB[$i]}"

    # Large textures
    if echo "$path" | grep -qiE '\.(png|jpg|jpeg|tga|psd|tif|tiff|bmp|exr)$'; then
        if (( $(echo "$size_kb > 2048" | bc 2>/dev/null || echo 0) )); then
            echo "  ${RED}[LARGE TEXTURE]${RESET} $(echo "scale=1; $size_kb / 1024" | bc) MB - $path"
            echo "    ${CYAN}Consider: compress texture, reduce resolution, or use crunch compression.${RESET}"
            ((issue_count++))
        fi
    fi

    # Large audio (uncompressed audio tends to be very large)
    if echo "$path" | grep -qiE '\.(wav|aiff|aif)$'; then
        if (( $(echo "$size_kb > 1024" | bc 2>/dev/null || echo 0) )); then
            echo "  ${RED}[UNCOMPRESSED AUDIO]${RESET} $(echo "scale=1; $size_kb / 1024" | bc) MB - $path"
            echo "    ${CYAN}Consider: use Vorbis/MP3 compression in the Audio import settings.${RESET}"
            ((issue_count++))
        fi
    fi

    # Large meshes
    if echo "$path" | grep -qiE '\.(fbx|obj|blend|dae|3ds|max)$'; then
        if (( $(echo "$size_kb > 5120" | bc 2>/dev/null || echo 0) )); then
            echo "  ${YELLOW}[LARGE MESH]${RESET} $(echo "scale=1; $size_kb / 1024" | bc) MB - $path"
            echo "    ${CYAN}Consider: reduce polygon count, use LODs, or optimize mesh in DCC tool.${RESET}"
            ((issue_count++))
        fi
    fi

    # Large videos
    if echo "$path" | grep -qiE '\.(mp4|mov|avi|webm)$'; then
        if (( $(echo "$size_kb > 10240" | bc 2>/dev/null || echo 0) )); then
            echo "  ${YELLOW}[LARGE VIDEO]${RESET} $(echo "scale=1; $size_kb / 1024" | bc) MB - $path"
            echo "    ${CYAN}Consider: reduce resolution/bitrate or stream from a URL instead.${RESET}"
            ((issue_count++))
        fi
    fi
done

# Check for included Editor-only assets (common mistake)
for path in "${ASSET_PATHS[@]}"; do
    if echo "$path" | grep -qi '/Editor/'; then
        echo "  ${YELLOW}[EDITOR ASSET IN BUILD]${RESET} $path"
        echo "    ${CYAN}Assets under Editor/ folders should not appear in builds. Check your build settings.${RESET}"
        ((issue_count++))
    fi
done

if (( issue_count == 0 )); then
    echo "  ${GREEN}No obvious issues detected in the build report.${RESET}"
fi

echo ""

# ---------------------------------------------------------------------------
# Category breakdown
# ---------------------------------------------------------------------------
echo "${BOLD}--- Category Breakdown ---${RESET}"
echo ""

declare -A CATEGORY_SIZE
categories=("Textures" "Audio" "Meshes" "Scripts" "Shaders" "Animations" "Fonts" "Other")

for path in "${ASSET_PATHS[@]}"; do
    idx=-1
    for i in "${!ASSET_PATHS[@]}"; do
        if [[ "${ASSET_PATHS[$i]}" == "$path" ]]; then
            idx=$i
            break
        fi
    done
    (( idx < 0 )) && continue
    size_kb="${ASSET_SIZES_KB[$idx]}"

    if echo "$path" | grep -qiE '\.(png|jpg|jpeg|tga|psd|tif|tiff|bmp|exr|tex)'; then
        CATEGORY_SIZE["Textures"]=$(echo "${CATEGORY_SIZE["Textures"]:-0} + $size_kb" | bc 2>/dev/null || echo "0")
    elif echo "$path" | grep -qiE '\.(wav|mp3|ogg|aiff|aif|flac)'; then
        CATEGORY_SIZE["Audio"]=$(echo "${CATEGORY_SIZE["Audio"]:-0} + $size_kb" | bc 2>/dev/null || echo "0")
    elif echo "$path" | grep -qiE '\.(fbx|obj|blend|dae|3ds|mesh)'; then
        CATEGORY_SIZE["Meshes"]=$(echo "${CATEGORY_SIZE["Meshes"]:-0} + $size_kb" | bc 2>/dev/null || echo "0")
    elif echo "$path" | grep -qiE '\.(cs|dll)'; then
        CATEGORY_SIZE["Scripts"]=$(echo "${CATEGORY_SIZE["Scripts"]:-0} + $size_kb" | bc 2>/dev/null || echo "0")
    elif echo "$path" | grep -qiE '\.(shader|shadergraph|hlsl|cginc|compute)'; then
        CATEGORY_SIZE["Shaders"]=$(echo "${CATEGORY_SIZE["Shaders"]:-0} + $size_kb" | bc 2>/dev/null || echo "0")
    elif echo "$path" | grep -qiE '\.(anim|controller|overridecontroller)'; then
        CATEGORY_SIZE["Animations"]=$(echo "${CATEGORY_SIZE["Animations"]:-0} + $size_kb" | bc 2>/dev/null || echo "0")
    elif echo "$path" | grep -qiE '\.(ttf|otf|fontsettings)'; then
        CATEGORY_SIZE["Fonts"]=$(echo "${CATEGORY_SIZE["Fonts"]:-0} + $size_kb" | bc 2>/dev/null || echo "0")
    else
        CATEGORY_SIZE["Other"]=$(echo "${CATEGORY_SIZE["Other"]:-0} + $size_kb" | bc 2>/dev/null || echo "0")
    fi
done

for cat in "${categories[@]}"; do
    size_kb="${CATEGORY_SIZE[$cat]:-0}"
    if (( $(echo "$size_kb > 0" | bc 2>/dev/null || echo 0) )); then
        if (( $(echo "$size_kb > 1024" | bc 2>/dev/null || echo 0) )); then
            printf "  %-14s %8.1f MB\n" "$cat:" "$(echo "scale=1; $size_kb / 1024" | bc)"
        else
            printf "  %-14s %8.1f KB\n" "$cat:" "$size_kb"
        fi
    fi
done

echo ""
echo "${GREEN}${BOLD}Analysis complete.${RESET}"
