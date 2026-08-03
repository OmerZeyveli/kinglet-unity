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
PROVIDER=""
while [ $# -gt 0 ]; do
    case "$1" in
        --facts-only) FACTS_ONLY=1; shift ;;
        --provider)   [ $# -ge 2 ] || { error "--provider needs a value"; exit 2; }
                      PROVIDER="$2"; shift 2 ;;
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
    # awk on the file, not `grep ... | head -1`: ProjectVersion.txt has both m_EditorVersion and
    # m_EditorVersionWithRevision, so the regex matches twice and head closes the pipe on grep —
    # a SIGPIPE that pipefail turns into a fatal error, but only when the writer is still writing.
    # It is a race that hides on small files and fires on big ones. Keying off the field name is
    # also just more correct than matching anything version-shaped.
    UNITY_VERSION=$(awk '/^m_EditorVersion:/ {print $2; exit}' "$VERSION_FILE")
    [ -n "$UNITY_VERSION" ] || UNITY_VERSION="unknown"
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
# 3b. Architecture stack — detected, never assumed
#
# .claude/rules/architecture.md mandates VContainer, MessagePipe, UniTask and
# Model-View-System; unity-specifics.md bans coroutines. Measured in the only
# real game project using this toolkit on 2026-08-03: VContainer 0 files,
# MessagePipe 0, UniTask 1, against 130 using StartCoroutine. Asserting a stack
# the project does not have is the largest single source of wrong guidance this
# toolkit ships, so it is detected and declared instead.
#
# WHAT IS SCANNED, and why it is not the obvious thing:
#   - Primary signal: Packages/manifest.json.
#   - Secondary signal: Assets/ ONLY, with vendored subtrees pruned.
# Scanning Packages/ would find the dependency's own source and report every
# project as using it. Vendored subtrees matter for the same reason at smaller
# scale: Endless-Evolution carries 923 third-party .cs files under
# Assets/Extensions/. A symbol found only in vendored code is not the project
# using it.
#
# One pass over the file list, testing all four symbols per file, rather than
# four passes: on a 1000-script project the difference is four thousand grep
# invocations against one thousand.
# ---------------------------------------------------------------------------
CS_FILE_COUNT=0
VC_REFS=0; MP_REFS=0; UT_REFS=0; COROUTINE_FILES=0

while IFS= read -r cs_file; do
    [ -n "$cs_file" ] || continue
    CS_FILE_COUNT=$((CS_FILE_COUNT + 1))
    # sort -u drains its input; no early-exit reader in this pipeline.
    #
    # `|| true` is load-bearing, not defensive noise. grep exits 1 when it matches
    # nothing, pipefail promotes that to the pipeline's status, the command
    # substitution inherits it, and under `set -e` a bare assignment with a failing
    # RHS terminates the script. The overwhelmingly common case on a real project is
    # a .cs file matching none of the four symbols, so without this the generator
    # dies on the first ordinary script and install.sh — which calls it with
    # `2>/dev/null` — writes no CLAUDE.md at all and prints one warning.
    hits=$(grep -o -e 'VContainer' -e 'MessagePipe' -e 'UniTask' -e 'StartCoroutine' \
                "$cs_file" 2>/dev/null | sort -u | tr '\n' ' ' || true)
    case "$hits" in *VContainer*)     VC_REFS=$((VC_REFS + 1)) ;; esac
    case "$hits" in *MessagePipe*)    MP_REFS=$((MP_REFS + 1)) ;; esac
    case "$hits" in *UniTask*)        UT_REFS=$((UT_REFS + 1)) ;; esac
    case "$hits" in *StartCoroutine*) COROUTINE_FILES=$((COROUTINE_FILES + 1)) ;; esac
done < <(find "$PROJECT_DIR/Assets" \
              \( -name Extensions -o -name Plugins -o -name ThirdParty -o -name Vendor \) -prune -o \
              -name '*.cs' -print 2>/dev/null || true)

# manifest_has <package-id> — the manifest is the primary signal.
manifest_has() {
    [ -f "$MANIFEST" ] || return 1
    grep -q "\"$1\"" "$MANIFEST"
}

# present <manifest-id> <ref-count> -> yes | manifest-only | no
#
# "manifest-only" is a real third state, not a rounding of "yes". A package
# declared and never used means the project has not committed to it, and this
# generator does not get to decide that for them.
present() {
    if manifest_has "$1"; then
        if [ "$2" -gt 0 ]; then printf 'yes'; else printf 'manifest-only'; fi
    elif [ "$2" -gt 0 ]; then printf 'yes'
    else printf 'no'; fi
}

VC_PRESENT=$(present jp.hadashikick.vcontainer "$VC_REFS")
MP_PRESENT=$(present com.cysharp.messagepipe  "$MP_REFS")
UT_PRESENT=$(present com.cysharp.unitask      "$UT_REFS")

info "Architecture stack: VContainer=$VC_PRESENT MessagePipe=$MP_PRESENT UniTask=$UT_PRESENT" \
     "(first-party .cs: $CS_FILE_COUNT, using StartCoroutine: $COROUTINE_FILES)"

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
# 6. Skills worth loading, by name
#
# Upstream suggested names like `unity-input-system` and `unity-general` that
# match nothing in .claude/skills/ — the names below are the real ones. They are
# bare names, not paths: skills live one level deep at .claude/skills/<name>/,
# because that is the only place Claude Code discovers them, and the name is
# what the Skill tool is invoked with.
# ---------------------------------------------------------------------------
suggest_skills() {
    local out=""
    while IFS= read -r pkg; do
        [ -n "$pkg" ] || continue
        case "$pkg" in
            "Input System")            out="${out}input-system"$'\n' ;;
            "Addressables")            out="${out}addressables"$'\n' ;;
            "UniTask")                 out="${out}unitask"$'\n' ;;
            "DOTween")                 out="${out}dotween"$'\n' ;;
            "TextMeshPro")             out="${out}textmeshpro"$'\n' ;;
            "Cinemachine")             out="${out}cinemachine"$'\n' ;;
            "AI Navigation")           out="${out}navmesh"$'\n' ;;
            "VContainer")              out="${out}vcontainer"$'\n' ;;
        esac
    done <<< "$DETECTED_PACKAGES"
    case "$RENDER_PIPELINE" in
        *URP*) out="${out}urp-pipeline"$'\n' ;;
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
        echo "**Skills matching this project** — load with the \`Skill\` tool by name."
        echo "Nothing loads them for you: no glob matching, no always-apply. A skill you do not"
        echo "invoke is a skill you do not have."
        echo ""
        printf '%s\n' "$SUGGESTED_SKILLS" | while IFS= read -r s; do [ -n "$s" ] && echo "- \`$s\`"; done
    fi
}

# Exactly what sits between the generated:begin/end markers, and the only
# producer of it. --facts-only used to call emit_facts directly, which left out
# the "## Project Facts" heading and the blank lines around it — so the
# documented use, refreshing an existing CLAUDE.md in place, quietly deleted the
# heading every time. Two code paths disagreeing about one region is the bug;
# one function is the fix.
# The section that stops this document asserting a stack the project does not
# have. It states which rules bind; it never deletes or disables a rule file.
#
# Field note 87, 2026-08-03: twelve headless runs, architecture.md present in
# one arm and deleted in the other. All twelve converged on the same design,
# and one run in the DELETED arm still wrote "not .claude/rules/architecture.md
# (no VContainer/MessagePipe here — see CLAUDE.md)". It rejected a file that was
# not there, because CLAUDE.md named it. The bulk layer steered nothing; one
# precedence sentence steered everything. Hence a sentence, not a deletion.
emit_stack_verdict() {
    echo ""
    echo "### Architecture stack — detected, not assumed"
    echo ""

    if [ "$CS_FILE_COUNT" -eq 0 ]; then
        # "Nothing is detected" was an overclaim: the manifest is read well before this point,
        # and a project that already declares VContainer is not a blank slate. Say what was
        # declared. `if`, not `manifest_has ... && x=...`: the && form returns 1 when the test
        # fails, and under `set -e` that ends the script.
        gf_declared=""
        if manifest_has jp.hadashikick.vcontainer; then gf_declared="${gf_declared}VContainer, "; fi
        if manifest_has com.cysharp.messagepipe;   then gf_declared="${gf_declared}MessagePipe, "; fi
        if manifest_has com.cysharp.unitask;       then gf_declared="${gf_declared}UniTask, "; fi
        gf_declared="${gf_declared%, }"

        if [ -n "$gf_declared" ]; then
            echo "No first-party C# under \`Assets/\` yet, so nothing is detected in code — but"
            echo "\`Packages/manifest.json\` already declares **$gf_declared**. That is a"
            echo "declaration, not a blank slate, and it is the closest thing to a decision this"
            echo "project has made."
        elif [ -f "$MANIFEST" ]; then
            echo "No first-party C# under \`Assets/\` yet, and \`Packages/manifest.json\` declares none"
            echo "of VContainer, MessagePipe or UniTask — so nothing is detected and nothing is"
            echo "contradicted."
        else
            echo "No first-party C# under \`Assets/\` yet, and there is no \`Packages/manifest.json\` to"
            echo "read — so nothing is detected and nothing is contradicted."
        fi
        echo ""
        echo "The toolkit's default stack — Model-View-System with VContainer, MessagePipe and"
        echo "UniTask — is therefore **recommended for this new project**, and every rule in"
        echo "\`.claude/rules/\` binds. Re-run the generator once there is code; if the project goes"
        echo "another way, this section will say so."
        return
    fi

    echo "Scanned \`Assets/\` (vendored subtrees excluded), $CS_FILE_COUNT first-party C# file(s):"
    echo ""
    echo "| Dependency | Present |"
    echo "|---|---|"
    echo "| VContainer | $VC_PRESENT ($VC_REFS file(s)) |"
    echo "| MessagePipe | $MP_PRESENT ($MP_REFS file(s)) |"
    echo "| UniTask | $UT_PRESENT ($UT_REFS file(s)) |"
    echo "| \`StartCoroutine\` | $COROUTINE_FILES file(s) |"
    echo ""

    # architecture.md rests on VContainer + MessagePipe. Either one present is
    # enough to keep it binding; "manifest-only" is deliberately neither.
    if [ "$VC_PRESENT" = yes ] || [ "$MP_PRESENT" = yes ]; then
        echo "\`.claude/rules/architecture.md\` **binds in full.**"
    elif [ "$VC_PRESENT" = manifest-only ] || [ "$MP_PRESENT" = manifest-only ]; then
        echo "A dependency is declared in \`Packages/manifest.json\` but used in no first-party file."
        echo "**This generator takes no side.** Decide whether \`.claude/rules/architecture.md\` binds"
        echo "here and write the answer in the Vision half of this document, outside the markers."
        echo ""
        echo "Until that decision is written down: \`csharp-unity.md\`, \`performance.md\` and"
        echo "\`serialization.md\` **bind** — they are architecture-agnostic and do not depend on the"
        echo "answer. The Model-View-System, VContainer and MessagePipe sections of"
        echo "\`architecture.md\` are **held in abeyance** — neither binding nor disapplied. Follow the"
        echo "architecture the code establishes as it is written, and record it here."
    else
        echo "The Model-View-System, VContainer and MessagePipe sections of \`.claude/rules/architecture.md\`"
        echo "**do not bind in this project** — they describe a stack this code does not use. Follow the"
        echo "architecture the code actually has. The rest of that file — \`ScriptableObjects for Static"
        echo "Data\`, \`Input System Architecture\`, \`No God Objects\`, \`Composition Over Inheritance\` —"
        echo "is architecture-agnostic and **does** apply."
    fi

    echo ""
    if [ "$UT_PRESENT" = yes ] && [ "$COROUTINE_FILES" -gt 0 ]; then
        # Both signals present. Deciding on UniTask alone got this wrong on the first real
        # project it met: 492 first-party files, ONE naming UniTask — a documentation spec
        # that mentions the word — against 38 genuinely using StartCoroutine. The output said
        # the no-coroutines rule binds, which is the opposite of what that code does.
        # A single reference does not outvote a pattern, and this generator does not get to
        # decide which one the project meant.
        echo "Mixed: $UT_REFS file(s) name UniTask and $COROUTINE_FILES use \`StartCoroutine\`."
        echo "**This generator takes no side** on the \"No Coroutines — Use UniTask\" section of"
        echo "\`unity-specifics.md\`. Decide it and write the answer outside the markers — and note"
        echo "that a lone UniTask reference is often a mention rather than a use."
    elif [ "$UT_PRESENT" = yes ]; then
        echo "The \"No Coroutines — Use UniTask\" section of \`unity-specifics.md\` **binds.**"
    elif [ "$UT_PRESENT" = manifest-only ]; then
        # manifest-only used to fall through to the else arm, which asserts "Neither UniTask nor
        # StartCoroutine appears" — flatly contradicting the table row directly above it, which
        # reads `manifest-only`. UniTask does appear; it appears in the manifest.
        echo "UniTask is declared in \`Packages/manifest.json\` but used in no first-party file,"
        echo "against $COROUTINE_FILES file(s) using \`StartCoroutine\`. **This generator takes no side**"
        echo "on the \"No Coroutines — Use UniTask\" section of \`unity-specifics.md\`. Decide it with"
        echo "the architecture question above and write the answer outside the markers."
    elif [ "$COROUTINE_FILES" -gt 0 ]; then
        echo "The \"No Coroutines — Use UniTask\" section of \`unity-specifics.md\` **does not bind** —"
        echo "$COROUTINE_FILES file(s) here use \`StartCoroutine\` and UniTask is not in use."
    else
        echo "Neither UniTask nor \`StartCoroutine\` appears; the async guidance in \`unity-specifics.md\`"
        echo "stands as a recommendation."
    fi

    echo ""
    echo "\`csharp-unity.md\`, \`performance.md\`, \`serialization.md\`, \`pc-console.md\` and the rest of"
    echo "\`unity-specifics.md\` **bind in full** regardless — they are architecture-agnostic, and"
    echo "\`[FormerlySerializedAs]\` and \`== null\` are exactly the rules that catch silent data loss."
}

# One sentence, not a routing block. Field note 87 measured that the bulk
# auto-loaded layer steered nothing while a single precedence sentence steered
# everything; a block here would be paying for the part that did not work.
emit_provider_verdict() {
    [ -n "$PROVIDER" ] || return 0
    [ "$PROVIDER" != none ] || return 0
    echo ""
    echo "### Process provider"
    echo ""
    echo "Discovery and written planning in this project are owned by \`$PROVIDER\`."
    echo "\`/unity-interview\` yields to it and does not compete for the discovery stage."
    echo "Unity implementation, Unity verification and Unity domain knowledge stay with this toolkit."
}

emit_marked_region() {
    echo ""
    echo "## Project Facts (auto-detected)"
    echo ""
    emit_facts
    emit_stack_verdict
    emit_provider_verdict
    echo ""
}

if [ "$FACTS_ONLY" -eq 1 ]; then
    emit_marked_region
    info "Emitted facts block only."
    exit 0
fi

cat <<'MDEOF'
# [FILL: Game Title] — Project Guide

> Unity 6 · C# · PC / Console · built with Kinglet Pioneer.

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

echo "<!-- kinglet:generated:begin — content between these markers is rewritten on re-install. Everything outside is yours. -->"
emit_marked_region
echo "<!-- kinglet:generated:end -->"

cat <<'MDEOF'

---

## Engineering Stance (fixed — do not casually change)

- **Engine / language:** Unity 6, C#.
- **Architecture:** see **Architecture stack — detected, not assumed** in the generated block above.
  That section is measured against this project's code and it is the authority; this list is not.
  The toolkit's default is Model-View-System with VContainer (DI), MessagePipe (cross-system
  messaging) and UniTask (async), and it is a default, not a finding.
- **Input:** the **New Input System**. Legacy `Input.*` is blocked by a hook, so this one is
  enforced rather than recommended.
- **Platform:** PC / console. No mobile code, touch input, or mobile performance budgets.
- **Rules** live in `.claude/rules/` and are binding:
  - `architecture.md` · `csharp-unity.md` · `performance.md` · `serialization.md` ·
    `unity-specifics.md` — the spine, **subject to the detected-stack section above.**
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
