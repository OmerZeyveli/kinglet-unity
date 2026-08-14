#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# validate-asmdefs.sh
# Assembly definition (.asmdef) graph checker for Unity projects.
# Validates reference integrity, detects circular dependencies, checks
# Editor/Test assembly conventions, and reports uncovered C# files.
#
# COVERAGE READS `.asmref` AS WELL AS `.asmdef`. An `.asmref` file adds its enclosing folder
# subtree to an assembly defined somewhere else, so Unity treats that subtree as covered. Until
# 2026-08-14 this script had never heard of the extension (`grep -rn asmref` over the whole toolkit
# returned nothing), and the coverage check counted every such file as uncovered. Measured on a real
# shipping project with 12 `.asmdef` and 29 `.asmref`: 21 warnings naming 800 files, all false.
#
# Requires: jq
#
# Usage:
#   ./scripts/validate-asmdefs.sh [--all]
#   In an installed Unity project this file is ./.claude/scripts/validate-asmdefs.sh.
#   --all   Include detailed per-assembly output.
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
${BOLD}validate-asmdefs.sh${RESET} - Assembly definition graph checker for Unity.

${BOLD}Usage:${RESET}
  ./scripts/validate-asmdefs.sh [--all]
  ./.claude/scripts/validate-asmdefs.sh [--all]  (the installed copy)

${BOLD}Options:${RESET}
  --all    Show detailed per-assembly information.
  --help   Show this help message.

${BOLD}Checks:${RESET}
  - Circular references between assemblies
  - Editor assemblies referencing runtime assemblies incorrectly
  - Test assemblies missing testOnly flag
  - .asmref files whose reference resolves to no assembly
  - C# files without assembly definition or reference coverage

${BOLD}Requirements:${RESET}
  jq (https://stedolan.github.io/jq/) must be installed.
EOF
    exit 0
fi

# ---------------------------------------------------------------------------
# Check jq
# ---------------------------------------------------------------------------
if ! command -v jq &>/dev/null; then
    echo "${RED}[ERROR]${RESET} jq is required but not installed."
    echo "  Install with: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
fi

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------
VERBOSE=false
[[ "${1:-}" == "--all" ]] && VERBOSE=true

# ---------------------------------------------------------------------------
# Locate project root
# ---------------------------------------------------------------------------
find_project_root() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/Assets" && -d "$dir/ProjectSettings" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

PROJECT_ROOT=$(find_project_root) || {
    echo "${RED}[ERROR]${RESET} Could not find Unity project root."
    exit 1
}

ASSETS_DIR="$PROJECT_ROOT/Assets"

echo ""
echo "${BOLD}=== Assembly Definition Validation ===${RESET}"
echo "  Project: $PROJECT_ROOT"
echo ""

error_count=0
warning_count=0

err()  { echo "  ${RED}[ERROR]${RESET} $*"; (( error_count += 1 )); }
warn_msg() { echo "  ${YELLOW}[WARN]${RESET}  $*"; (( warning_count += 1 )); }
info() { echo "  ${CYAN}[INFO]${RESET}  $*"; }

# ---------------------------------------------------------------------------
# 1. Collect all .asmdef files
#
# Seven `declare -A` maps become parallel indexed arrays, not seven separate tables: six of the
# seven were keyed on the same thing (assembly `name`) — ASMDEF_NAME_TO_PATH, ASMDEF_REFS,
# ASMDEF_DIR, ASMDEF_IS_EDITOR, ASMDEF_IS_TEST, ASMDEF_TEST_ONLY — so index i in every array below
# is one record: the i-th assembly discovered. ASMDEF_PATHS[i] is that assembly's path, which is
# what ASMDEF_PATH_TO_NAME existed for; it was written but never read anywhere in this script, and
# is fully recoverable from ASMDEF_PATHS[i] if something needs it later, so it is not resurrected
# as a separate reverse-lookup structure here.
#
# Name -> index lookups (needed for duplicate detection and for resolving a reference name to the
# assembly it points at) use a linear scan (asmdef_index_of_name, below) rather than a sanitised
# `printf -v` variable name per assembly. Two reasons: assembly counts are small (tens, maybe a
# few hundred even in a large studio — nothing like the tens-of-thousands .meta-file scale that
# made detect-missing-refs.sh and validate-meta-integrity.sh need a real lookup structure), so O(n)
# per lookup costs nothing here; and assembly names contain dots (e.g. "MyCompany.MyGame.Core"),
# which are illegal in bash identifiers, so a `printf -v`-based scheme would need its own
# collision-free sanitisation — a second problem to get right for no measurable win at this scale.
#
# ASMDEF_REFS[i] holds jq's reference-list output with internal newlines converted to spaces:
# a `<TAB>`-delimited record can't carry an embedded newline in one field, and the original already
# consumed this value with `for ref in $refs`, which word-splits on any whitespace — so joining on
# spaces instead of newlines changes nothing about how it's read.
ASMDEF_NAMES=()
ASMDEF_PATHS=()
ASMDEF_DIRS=()
ASMDEF_REFS=()
ASMDEF_IS_EDITOR=()
ASMDEF_IS_TEST=()
ASMDEF_TEST_ONLY=()

asmdef_count=0

# Read a Unity .meta file's guid. An `.asmref` in GUID form points at the `.asmdef`'s **`.meta`
# file** guid, not at anything inside the `.asmdef` itself, so resolving one means reading
# `<path-to-asmdef>.meta` and matching its `guid:` line.
#
# awk reads the file directly rather than being fed by a pipe. `exit` inside a rule is precisely the
# early-exiting reader this repository's shell notes warn about — but only when something upstream is
# still writing. There is no writer here, so there is no SIGPIPE to promote. `exit` in a rule falls
# through to END, which supplies status 1 when no guid line was ever seen.
meta_guid_of() {
    local meta="$1.meta"
    [[ -f "$meta" ]] || return 1
    awk '$1 == "guid:" { print $2; seen = 1; exit } END { if (!seen) exit 1 }' "$meta"
}

# Linear scan for the index of `target` in ASMDEF_NAMES. Prints the index and returns 0 if found;
# returns 1 (nothing printed) otherwise. Assembly counts don't justify anything smarter — see the
# note above ASMDEF_NAMES.
asmdef_index_of_name() {
    local target="$1"
    local i
    for ((i = 0; i < ${#ASMDEF_NAMES[@]}; i++)); do
        if [[ "${ASMDEF_NAMES[$i]}" == "$target" ]]; then
            echo "$i"
            return 0
        fi
    done
    return 1
}

while IFS= read -r -d '' asmdef_file; do
    (( asmdef_count += 1 ))

    # Parse JSON
    name=$(jq -r '.name // empty' "$asmdef_file" 2>/dev/null || true)
    if [[ -z "$name" ]]; then
        warn_msg "Could not parse name from: ${asmdef_file#"$PROJECT_ROOT/"}"
        continue
    fi

    # Check for duplicate names
    if existing_idx=$(asmdef_index_of_name "$name"); then
        err "Duplicate assembly name '$name':"
        echo "         ${ASMDEF_PATHS[$existing_idx]#"$PROJECT_ROOT/"}"
        echo "         ${asmdef_file#"$PROJECT_ROOT/"}"
        continue
    fi

    idx=${#ASMDEF_NAMES[@]}
    ASMDEF_NAMES[idx]="$name"
    ASMDEF_PATHS[idx]="$asmdef_file"
    ASMDEF_DIRS[idx]="$(dirname "$asmdef_file")"

    # Extract references (can be plain names or GUIDs in GUID: format)
    refs_raw=$(jq -r '(.references // [])[] | select(startswith("GUID:") | not)' "$asmdef_file" 2>/dev/null || true)
    ASMDEF_REFS[idx]=$(printf '%s' "$refs_raw" | tr '\n' ' ')

    # HERE-STRINGS, NOT `echo "$VAR" | grep -q…`, throughout this block. `grep -q` exits the instant
    # it matches without draining stdin; if the writer is still writing it takes SIGPIPE, pipefail
    # reports 141 for the whole pipeline, and because these all sit in an `if` CONDITION (where
    # `set -e` is suspended) the script does not die — it takes the `else` branch. A match that IS
    # there is reported as absent. That is fail-open: an Editor/Runtime violation goes unreported and
    # the run still says "No violations".
    #
    # WHAT DECIDES IT IS SHAPE, NOT SIZE — measured 2026-08-14 at 1 KB / 50 KB / 120 KB / 400 KB.
    # A ONE-LINE haystack never fires at any size: grep cannot decide a line until it has all of it,
    # so it drains its input and the writer never sees a closed pipe. The SAME BYTES
    # newline-separated fail open from about 50 KB up. `$include_platforms` and
    # `$define_constraints` are `jq -r '…[]'` output — one array element per line, i.e. exactly the
    # multi-line shape — and defineConstraints is author-written with no ceiling. `$name` is one
    # short token. None of them is large enough today; the point is that nothing keeps them small,
    # and the here-string costs nothing. bash writes a here-string out before grep is exec'd, so
    # there is no live writer for grep's early exit to signal.
    #
    # tests/test-bash32-compat.sh now sweeps scripts/ for both readers, so this shape cannot return
    # here unnoticed.

    # Determine if Editor assembly
    asmdef_dir_lower=$(echo "${ASMDEF_DIRS[idx]}" | tr '[:upper:]' '[:lower:]')
    include_platforms=$(jq -r '(.includePlatforms // [])[]' "$asmdef_file" 2>/dev/null || true)
    is_editor=false
    if grep -qi 'editor' <<< "$include_platforms"; then
        is_editor=true
    elif [[ "$asmdef_dir_lower" == */editor* ]] || grep -qi '\.editor' <<< "$name"; then
        is_editor=true
    fi
    ASMDEF_IS_EDITOR[idx]="$is_editor"

    # Determine if Test assembly
    is_test=false
    if [[ "$asmdef_dir_lower" == */tests* ]] || [[ "$asmdef_dir_lower" == */test* ]] || grep -qi '\.tests\|\.test' <<< "$name"; then
        is_test=true
    fi
    override_refs=$(jq -r '(.overrideReferences // false)' "$asmdef_file" 2>/dev/null || true)
    define_constraints=$(jq -r '(.defineConstraints // [])[]' "$asmdef_file" 2>/dev/null || true)
    if grep -q 'UNITY_INCLUDE_TESTS' <<< "$define_constraints"; then
        is_test=true
    fi
    ASMDEF_IS_TEST[idx]="$is_test"

    # testOnly field (Unity doesn't have this natively, but some projects use defineConstraints)
    # We consider it "test only" if defineConstraints includes UNITY_INCLUDE_TESTS
    test_only=false
    if grep -q 'UNITY_INCLUDE_TESTS' <<< "$define_constraints"; then
        test_only=true
    fi
    ASMDEF_TEST_ONLY[idx]="$test_only"

    if $VERBOSE; then
        info "Assembly: $name (editor=$is_editor, test=$is_test)"
    fi
done < <(find "$ASSETS_DIR" -name '*.asmdef' -print0 2>/dev/null)

info "Found $asmdef_count assembly definition(s)."
echo ""

if (( asmdef_count == 0 )); then
    warn_msg "No .asmdef files found. Consider adding assembly definitions."
    echo ""
    echo "${YELLOW}${BOLD}DONE${RESET} - No assemblies to validate."
    exit 0
fi

# ---------------------------------------------------------------------------
# 2. Detect circular references (DFS cycle detection)
# ---------------------------------------------------------------------------
echo "${BOLD}--- Circular Reference Check ---${RESET}"

# VISIT_STATE indexed the same way as ASMDEF_NAMES/ASMDEF_REFS/etc: index i is this assembly's DFS
# state (0=unvisited, 1=in-progress, 2=done). It is mutated on every recursive call, which is the
# actual design question here (not just "which container type") — a structure rewritten wholesale
# per mutation would make each visit O(n) inside an already-recursive walk. A single-element
# indexed-array write, `VISIT_STATE[idx]=1`, is O(1) regardless of how many assemblies exist, same
# as the `declare -A` version was, so nothing is lost by leaving `declare -A` behind here.
VISIT_STATE=()
for ((vi = 0; vi < ${#ASMDEF_NAMES[@]}; vi++)); do
    VISIT_STATE[vi]=0
done
cycle_found=false

detect_cycle() {
    local idx="$1"
    local path="$2"

    VISIT_STATE[idx]=1  # in-progress

    local refs="${ASMDEF_REFS[$idx]:-}"
    local ref ref_idx state
    for ref in $refs; do
        # Skip references to assemblies not in our project (Unity packages etc.)
        ref_idx=$(asmdef_index_of_name "$ref") || continue

        state="${VISIT_STATE[$ref_idx]}"
        if (( state == 1 )); then
            err "Circular reference detected: ${path} -> ${ref}"
            cycle_found=true
        elif (( state == 0 )); then
            detect_cycle "$ref_idx" "${path} -> ${ref}"
        fi
    done

    VISIT_STATE[idx]=2  # done
}

for ((di = 0; di < ${#ASMDEF_NAMES[@]}; di++)); do
    if [[ "${VISIT_STATE[$di]}" == "0" ]]; then
        detect_cycle "$di" "${ASMDEF_NAMES[$di]}"
    fi
done

if ! $cycle_found; then
    echo "  ${GREEN}No circular references found.${RESET}"
fi

echo ""

# ---------------------------------------------------------------------------
# 3. Editor assembly checks
# ---------------------------------------------------------------------------
echo "${BOLD}--- Editor Assembly Checks ---${RESET}"
editor_issues=false

for ((ei = 0; ei < ${#ASMDEF_NAMES[@]}; ei++)); do
    name="${ASMDEF_NAMES[$ei]}"
    is_editor="${ASMDEF_IS_EDITOR[$ei]}"

    if [[ "$is_editor" == "true" ]]; then
        # Editor assemblies should not be referenced by runtime assemblies
        for ((ej = 0; ej < ${#ASMDEF_NAMES[@]}; ej++)); do
            (( ej == ei )) && continue
            [[ "${ASMDEF_IS_EDITOR[$ej]}" == "true" ]] && continue
            [[ "${ASMDEF_IS_TEST[$ej]}" == "true" ]] && continue

            other_name="${ASMDEF_NAMES[$ej]}"
            other_refs="${ASMDEF_REFS[$ej]:-}"
            # Task 9 left this as `echo "$other_refs" | grep -qw "$name"` on the ground that the
            # reference list is "bounded in practice". Re-run 2026-08-14, that ground is the wrong
            # reason for a right answer: measured at 1 KB / 50 KB / 120 KB / 400 KB, the one-line
            # form of this pipeline never fires at ANY size (grep must read a whole line before it
            # can decide, so it drains its writer), while the same bytes newline-separated fail open
            # from ~50 KB. What makes this line safe is therefore the `tr '\n' ' '` at the
            # ASMDEF_REFS assignment above, which flattens jq's per-line output into a single line —
            # not the number of references. Delete that `tr` and this becomes a live fail-open bug
            # at a size no test in this repo constructs.
            #
            # Converted anyway: a here-string is safe under BOTH shapes, so it stops depending on a
            # property of a line seventy lines away that nothing asserts.
            if grep -qw "$name" <<< "$other_refs"; then
                err "Runtime assembly '$other_name' references Editor assembly '$name'."
                editor_issues=true
            fi
        done
    fi
done

if ! $editor_issues; then
    echo "  ${GREEN}No Editor/Runtime reference violations.${RESET}"
fi

echo ""

# ---------------------------------------------------------------------------
# 4. Test assembly checks
# ---------------------------------------------------------------------------
echo "${BOLD}--- Test Assembly Checks ---${RESET}"
test_issues=false

for ((ti = 0; ti < ${#ASMDEF_NAMES[@]}; ti++)); do
    name="${ASMDEF_NAMES[$ti]}"
    is_test="${ASMDEF_IS_TEST[$ti]}"
    test_only="${ASMDEF_TEST_ONLY[$ti]}"

    if [[ "$is_test" == "true" && "$test_only" == "false" ]]; then
        warn_msg "Test assembly '$name' lacks UNITY_INCLUDE_TESTS defineConstraint. It may be included in production builds."
        test_issues=true
    fi
done

if ! $test_issues; then
    echo "  ${GREEN}All test assemblies properly configured.${RESET}"
fi

echo ""

# ---------------------------------------------------------------------------
# 5. Assembly reference (.asmref) files
#
# An `.asmref` is JSON with a single `reference` key and it takes two forms, both of which occur in
# the wild — on the project this check was measured against the GUID form outnumbered the name form
# more than 2:1, so neither can be treated as the special case:
#
#     {"reference":"MyGame.Runtime"}                          by assembly NAME
#     {"reference":"GUID:4a1cb1490dc4df8409b2580d6b44e75e"}   by the target .asmdef.meta's guid
#
# RESOLUTION SCOPE is Assets/ plus Packages/, not Assets/ alone. The graph checks above index only
# Assets/, but an `.asmref` may legitimately target an assembly defined by an embedded package, and
# resolving against Assets/ alone would report that as dangling — trading one class of false positive
# for another. Library/PackageCache is deliberately out of scope: it is a build artifact that a fresh
# clone does not have, so a check that depended on it would give different answers on the same
# commit. The warning text below names the scope so a reader can tell a genuine dangle from a target
# this script cannot see.
# ---------------------------------------------------------------------------
echo "${BOLD}--- Assembly Reference (.asmref) Check ---${RESET}"

ASMREF_DIRS=()
asmref_count=0
asmref_dangling=0

# Resolution index, separate from the graph arrays on purpose: it spans a wider root set and it must
# not feed cycle detection or the Editor/Runtime rules, which are defined over the project's own
# assemblies. Built only when there is at least one .asmref to resolve.
REFTARGET_NAMES=()
REFTARGET_GUIDS=()

reftarget_resolves() {
    # $1 = "name:<assembly name>" or "guid:<hex>". Prints nothing; returns 0 when a target exists.
    local kind="${1%%:*}" want="${1#*:}" i
    if [[ "$kind" == "guid" ]]; then
        for ((i = 0; i < ${#REFTARGET_GUIDS[@]}; i++)); do
            [[ -n "${REFTARGET_GUIDS[$i]}" && "${REFTARGET_GUIDS[$i]}" == "$want" ]] && return 0
        done
    else
        for ((i = 0; i < ${#REFTARGET_NAMES[@]}; i++)); do
            [[ "${REFTARGET_NAMES[$i]}" == "$want" ]] && return 0
        done
    fi
    return 1
}

# `find -print0` with `read -r -d ''`, not `for f in $(find …)`. Real projects carry folders with
# spaces in them — the measurement that produced this check hit `Assets/Core/World Level/Editor/`
# and `Assets/Player/DNA Forms/` — and word-splitting turns each of those into two nonexistent paths.
#
# Discovery is a separate pass from resolution so the count is known before the resolution index is
# built: a project with no `.asmref` at all should not pay for a second `find`. The paths are held in
# an ARRAY rather than joined into a newline-delimited string, because joining on newlines hands back
# exactly the separator `-print0` was chosen to avoid.
ASMREF_PATHS=()
while IFS= read -r -d '' asmref_file; do
    ASMREF_PATHS[asmref_count]="$asmref_file"
    (( asmref_count += 1 ))
done < <(find "$ASSETS_DIR" -name '*.asmref' -print0 2>/dev/null)

if (( asmref_count > 0 )); then
    reftarget_roots=("$ASSETS_DIR")
    [[ -d "$PROJECT_ROOT/Packages" ]] && reftarget_roots+=("$PROJECT_ROOT/Packages")

    while IFS= read -r -d '' target_asmdef; do
        ti=${#REFTARGET_NAMES[@]}
        REFTARGET_NAMES[ti]="$(jq -r '.name // empty' "$target_asmdef" 2>/dev/null || true)"
        REFTARGET_GUIDS[ti]="$(meta_guid_of "$target_asmdef" || true)"
    done < <(find "${reftarget_roots[@]}" -name '*.asmdef' -print0 2>/dev/null)

    for ((ri = 0; ri < asmref_count; ri++)); do
        asmref_file="${ASMREF_PATHS[$ri]}"
        rel="${asmref_file#"$PROJECT_ROOT/"}"
        ref=$(jq -r '.reference // empty' "$asmref_file" 2>/dev/null || true)

        if [[ -z "$ref" ]]; then
            warn_msg "Unresolvable .asmref: $rel has no readable 'reference' key."
            (( asmref_dangling += 1 ))
        elif [[ "$ref" == GUID:* ]]; then
            if reftarget_resolves "guid:${ref#GUID:}"; then
                if $VERBOSE; then info ".asmref $rel -> ${ref#GUID:} (by GUID)"; fi
            else
                warn_msg "Unresolvable .asmref: $rel references ${ref}, which matches no .asmdef.meta guid under Assets/ or Packages/. Files in that subtree are reported as covered below, but their assembly membership is NOT verified."
                (( asmref_dangling += 1 ))
            fi
        else
            if reftarget_resolves "name:$ref"; then
                if $VERBOSE; then info ".asmref $rel -> $ref (by name)"; fi
            else
                warn_msg "Unresolvable .asmref: $rel references assembly '$ref', which no .asmdef under Assets/ or Packages/ defines. Files in that subtree are reported as covered below, but their assembly membership is NOT verified."
                (( asmref_dangling += 1 ))
            fi
        fi

        ASMREF_DIRS[ri]="$(dirname "$asmref_file")"
    done
fi

info "Found $asmref_count assembly reference(s)."
if (( asmref_dangling == 0 )); then
    echo "  ${GREEN}All .asmref references resolve to an assembly.${RESET}"
fi

echo ""

# ---------------------------------------------------------------------------
# 6. Files without assembly definition coverage
#
# A DANGLING `.asmref` STILL GRANTS COVERAGE HERE, and that is a decision rather than an oversight.
# The folder is claimed by an assembly file; what is broken is the reference, and section 5 has
# already named it, once, with the subtree it affects. Withholding coverage instead would re-report
# the same single defect once per C# file underneath — on the measured project a single dangling
# third-party `.asmref` would have restored hundreds of warnings, which is precisely the noise this
# section was fixed to stop emitting.
# ---------------------------------------------------------------------------
echo "${BOLD}--- Uncovered C# Files ---${RESET}"
uncovered_count=0

# Both file kinds cover their subtree, so both go in one list.
covered_dirs=("${ASMDEF_DIRS[@]}")
if (( asmref_count > 0 )); then
    covered_dirs+=("${ASMREF_DIRS[@]}")
fi

is_covered() {
    local cs_dir="$1"
    local adir
    for adir in "${covered_dirs[@]}"; do
        # THE `/` MATTERS. This was a bare `"$cs_dir" == "$adir"*` prefix test, which is a fail-open
        # the moment one covered directory's name is a prefix of a sibling's: with an assembly file
        # at `Assets/Player`, everything under `Assets/PlayerPrefsEditor` read as covered. Latent
        # while only .asmdef directories were listed here, and live the instant .asmref directories
        # joined them — the measured project has exactly that Player / PlayerPrefsEditor pair.
        if [[ "$cs_dir" == "$adir" || "$cs_dir" == "$adir"/* ]]; then
            return 0
        fi
    done
    return 1
}

while IFS= read -r -d '' csfile; do
    cs_dir="$(dirname "$csfile")"
    if ! is_covered "$cs_dir"; then
        rel="${csfile#"$PROJECT_ROOT/"}"
        if (( uncovered_count < 20 )); then
            warn_msg "No .asmdef/.asmref coverage: $rel"
        fi
        (( uncovered_count += 1 ))
    fi
done < <(find "$ASSETS_DIR" -name '*.cs' -not -path '*/Editor/*' -print0 2>/dev/null)

if (( uncovered_count > 20 )); then
    warn_msg "... and $(( uncovered_count - 20 )) more uncovered files."
fi

if (( uncovered_count == 0 )); then
    echo "  ${GREEN}All C# files are covered by an assembly definition or reference.${RESET}"
else
    echo "  ${YELLOW}$uncovered_count file(s) without assembly definition or reference coverage.${RESET}"
fi

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "${BOLD}=== Summary ===${RESET}"
echo "  Assemblies found : $asmdef_count"
echo "  References found : $asmref_count"
echo "  Errors           : $error_count"
echo "  Warnings         : $warning_count"

if (( error_count > 0 )); then
    echo ""
    echo "${RED}${BOLD}FAILED${RESET} - $error_count error(s) found."
    exit 1
elif (( warning_count > 0 )); then
    echo ""
    echo "${YELLOW}${BOLD}PASSED WITH WARNINGS${RESET} - $warning_count warning(s)."
    exit 0
else
    echo ""
    echo "${GREEN}${BOLD}PASSED${RESET} - All assembly definitions valid."
    exit 0
fi
