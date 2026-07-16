#!/usr/bin/env bash
# ============================================================================
# instinct-distill.sh — STOP HOOK (strict profile)
# Reads observations.jsonl and extracts atomic instincts with confidence
# scores. Heuristic-only (no LLM); cheap and deterministic.
#
# Heuristics (v1):
#   H1 — Warning-hotspot: if path_tag X raises warnings in >=30% of tool-uses
#        AND has >=3 observations, emit an instinct.
#   H2 — Tool-sequence: if edits to path_tag X are consistently preceded by
#        Reads of a related tag, emit an instinct.
#   H3 — Hook-specific recurrence: a hook that fires >=3 times this session
#        on the same path_tag becomes a project-level signal.
#
# Instinct storage: JSON per instinct at
#   .claude/state/instincts/project/<project-hash>/<id>.json
# Confidence starts at 0.3, increases by 0.1 per fresh evidence up to 0.9.
# ============================================================================
# Trigger: Stop
# Exit:    0 always
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="strict"
source "${SCRIPT_DIR}/_lib.sh"

OBS="$UNITY_OBSERVATIONS_FILE"
[ -f "$OBS" ] || exit 0
[ -s "$OBS" ] || exit 0

PROJECT_HASH="$(unity_project_hash)"
PROJECT_DIR="${UNITY_INSTINCTS_DIR}/project/${PROJECT_HASH}"
mkdir -p "$PROJECT_DIR"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---------------------------------------------------------------------------
# upsert_instinct — idempotent write with evidence-count bump and confidence
# floor/ceiling. Arguments: id, trigger, action, domain
# ---------------------------------------------------------------------------
upsert_instinct() {
    local id="$1"
    local trigger="$2"
    local action="$3"
    local domain="$4"
    local file="${PROJECT_DIR}/${id}.json"

    if [ -f "$file" ]; then
        # Bump evidence count, nudge confidence toward 0.9 (add 0.1, cap at 0.9)
        jq --arg ts "$TS" '
            .evidence_count = (.evidence_count + 1) |
            .last_seen = $ts |
            .confidence = ( [ (.confidence + 0.1), 0.9 ] | min )
        ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    else
        # Fresh instinct: confidence 0.3, evidence 1
        jq -n \
            --arg id "$id" \
            --arg trigger "$trigger" \
            --arg action "$action" \
            --arg domain "$domain" \
            --arg project "$PROJECT_HASH" \
            --arg ts "$TS" \
            '{
                id: $id,
                trigger: $trigger,
                action: $action,
                confidence: 0.3,
                domain: $domain,
                scope: "project",
                project_id: $project,
                evidence_count: 1,
                first_seen: $ts,
                last_seen: $ts,
                source: "auto-distill"
            }' > "$file"
    fi
}

# Only consider observations for this project
PROJ_OBS=$(jq -c --arg p "$PROJECT_HASH" 'select(.project == $p)' "$OBS" 2>/dev/null || echo "")
if [ -z "$PROJ_OBS" ]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# H1 — Warning-hotspot by path_tag
# ---------------------------------------------------------------------------
# Group by path_tag, compute:
#   total    = observations in that tag this session
#   warn     = observations where warning_count > max_warning_before_tag
# A simple approximation: per-tag warning delta (last - first) >= 3 flags hot.
#
# Because warning_count is cumulative across all tools, we approximate
# "warnings-during-this-tag" as: max(warning_count) - min(warning_count)
# among observations in that tag, compared to total observations in that tag.
# ---------------------------------------------------------------------------

TAG_STATS=$(echo "$PROJ_OBS" | jq -s '
    group_by(.path_tag) |
    map({
        tag: .[0].path_tag,
        total: length,
        warn_delta: ((map(.warning_count) | max) - (map(.warning_count) | min))
    }) |
    map(select(.tag != "other" and .total >= 3 and .warn_delta >= 2))
')

echo "$TAG_STATS" | jq -c '.[]' 2>/dev/null | while read -r row; do
    TAG=$(echo "$row" | jq -r '.tag')

    case "$TAG" in
        view)    TRIG="before editing *View.cs" ; ACTION="expect quality-gate warnings; confirm the Model is read first and no Update-loop allocations are introduced" ; DOMAIN="mvs" ;;
        system)  TRIG="before editing *System.cs" ; ACTION="confirm VContainer registration is consistent; System owns Model mutations, not Views" ; DOMAIN="mvs" ;;
        model)   TRIG="before editing *Model.cs" ; ACTION="keep Models pure C#; no MonoBehaviour, no Unity API references" ; DOMAIN="mvs" ;;
        sobject) TRIG="before editing a ScriptableObject type" ; ACTION="SO holds static config; runtime mutable state belongs in a Model" ; DOMAIN="data" ;;
        mono)    TRIG="before editing a MonoBehaviour Controller/Manager/Handler" ; ACTION="watch for GetComponent/Camera.main/allocations in Update loops" ; DOMAIN="perf" ;;
        scene)   TRIG="before editing a .unity scene file" ; ACTION="use unity-mcp scene tools, not raw text edits; diffs corrupt GUIDs" ; DOMAIN="safety" ;;
        prefab)  TRIG="before editing a .prefab file" ; ACTION="prefer unity-mcp prefab tools; manual YAML edits break FormerlySerializedAs chains" ; DOMAIN="safety" ;;
        editor)  TRIG="before editing Editor/ code" ; ACTION="wrap UnityEditor usage in #if UNITY_EDITOR when the file lives outside Editor/" ; DOMAIN="platform" ;;
        *) continue ;;
    esac

    ID="h1-${TAG}-warning-hotspot"
    upsert_instinct "$ID" "$TRIG" "$ACTION" "$DOMAIN"
done

# ---------------------------------------------------------------------------
# H2 — Tool sequence: Edit <tag> frequently preceded by Read <related-tag>
# ---------------------------------------------------------------------------
# Simpler proxy: for each Edit on *View.cs, check if a *Model.cs Read
# preceded it in the same session. If ratio >= 0.5, that's the de facto
# workflow.
# ---------------------------------------------------------------------------

VIEW_EDITS=$(echo "$PROJ_OBS" | jq -s '[ .[] | select(.tool=="Edit" or .tool=="Write") | select(.path_tag=="view") ] | length' 2>/dev/null || echo 0)
MODEL_READS=$(echo "$PROJ_OBS" | jq -s '[ .[] | select(.tool=="Read") | select(.path_tag=="model") ] | length' 2>/dev/null || echo 0)

if [ "${VIEW_EDITS:-0}" -ge 2 ] && [ "${MODEL_READS:-0}" -ge 1 ]; then
    upsert_instinct \
        "h2-read-model-before-view" \
        "before editing *View.cs" \
        "read the paired *Model.cs first (observed pattern on this project)" \
        "mvs"
fi

# ---------------------------------------------------------------------------
# H3 — Hook-specific recurrence: warnings fired >=3 times
# ---------------------------------------------------------------------------
if [ -f "$UNITY_WARNINGS_FILE" ]; then
    # warnings look like "hook-name: message" — group by hook-name
    awk -F: '{print $1}' "$UNITY_WARNINGS_FILE" | sort | uniq -c | while read -r count hook; do
        if [ "${count:-0}" -ge 3 ]; then
            case "$hook" in
                warn-serialization)
                    upsert_instinct "h3-serialization-recurrence" \
                        "when adding [SerializeField] fields" \
                        "always include [FormerlySerializedAs] on renames; warn-serialization fired 3+ times this session" \
                        "serialization" ;;
                warn-filename)
                    upsert_instinct "h3-filename-recurrence" \
                        "when creating/renaming C# files" \
                        "filename must match the primary type; check before writing" \
                        "style" ;;
                warn-platform-defines)
                    upsert_instinct "h3-platform-recurrence" \
                        "when using UnityEditor or platform APIs" \
                        "guard with #if UNITY_EDITOR / UNITY_ANDROID etc. with fallback branches" \
                        "platform" ;;
                quality-gate)
                    upsert_instinct "h3-quality-recurrence" \
                        "when editing hot-path code (Update/FixedUpdate/LateUpdate)" \
                        "avoid GetComponent/FindObjectOfType/allocations; cache references in Awake" \
                        "perf" ;;
                gateguard)
                    upsert_instinct "h3-gateguard-recurrence" \
                        "when starting work on a C# file" \
                        "Read and fact-gather before the first Edit; GateGuard blocked 3+ times" \
                        "process" ;;
            esac
        fi
    done
fi

exit 0
