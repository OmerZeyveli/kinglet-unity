#!/usr/bin/env bash
#
# mkproject.sh — build a synthetic Unity project to test the installer against.
#
# This repo is not a Unity project, and install.sh gates on Assets/ + ProjectSettings/. Everything
# the installer scans is plain text, so a directory with the right shape exercises it fully.
#
# Usage:
#   ./tests/fixtures/mkproject.sh <dir> [--variant urp|builtin|bare|dirty|legacy|async-mixed|hdrp|both|asmref]
#
#   urp      (default) URP + Input System + UniTask + VContainer, one asmdef, one scene
#   builtin  Built-in pipeline, minimal packages
#   bare     No Packages/, no .gitignore, no scenes — the "nothing to detect" path
#   dirty    urp + a pre-existing CLAUDE.md and .claude/, for the upgrade/guard paths
#   legacy   URP, no VContainer/MessagePipe/UniTask, coroutine-using scripts — the "does not bind" path
#   async-mixed  UniTask named once (in a doc spec) against two coroutine users — the "takes no side" path
#   hdrp     HDRP only — the pipeline token no fixture produced until 2026-08-13
#   both     URP *and* HDRP present — the token neither pre-detector implementation had at all
#   asmref   One .asmdef whose scope is extended by four .asmref files — the assembly shape no
#            fixture here had until 2026-08-14. See the block above the case arm.
#
# WHY `hdrp` AND `both` EXIST. Until 2026-08-13 every fixture here produced one of two pipeline
# tokens, `urp` or `builtin`. install.sh and scripts/generate-claude-md.sh each carried their own
# copy of the detection, and the two DISAGREED — install.sh's unconditional greps let HDRP win,
# generate-claude-md.sh's if/elif let URP win — yet the whole suite stayed green, because no
# fixture ever reached a manifest where the two could differ. The fixture set, not the code, was
# what made the defect invisible. These two are the discriminating inputs: `hdrp` separates the two
# single-pipeline answers, and `both` is the state neither implementation had.
#
set -euo pipefail

DIR="${1:-}"; shift || true
[ -n "$DIR" ] || { echo "usage: mkproject.sh <dir> [--variant urp|builtin|bare|dirty|legacy|async-mixed|hdrp|both|asmref]" >&2; exit 2; }

VARIANT=urp
while [ $# -gt 0 ]; do
  case "$1" in
    --variant) [ $# -ge 2 ] || { echo "err: --variant needs a value" >&2; exit 2; }; VARIANT="$2"; shift 2 ;;
    *) echo "err: unknown argument $1" >&2; exit 2 ;;
  esac
done

rm -rf "$DIR"
mkdir -p "$DIR/Assets/Scripts" "$DIR/ProjectSettings"
# Both lines, as Unity actually writes them. A one-line fixture hid a real bug: the version regex
# matches twice here, and `grep | head -1` SIGPIPEs the grep once the output is big enough to still
# be writing when head exits.
cat > "$DIR/ProjectSettings/ProjectVersion.txt" <<'EOF'
m_EditorVersion: 6000.0.23f1
m_EditorVersionWithRevision: 6000.0.23f1 (b2c3d4e5f6a7)
EOF

if [ "$VARIANT" != bare ]; then
  mkdir -p "$DIR/Packages" "$DIR/Assets/Scenes"
  cat > "$DIR/Assets/Scripts/Gameplay.asmdef" <<'JSON'
{
  "name": "Game.Gameplay",
  "rootNamespace": "Game.Gameplay",
  "references": []
}
JSON
  : > "$DIR/Assets/Scenes/Main.unity"
  cat > "$DIR/ProjectSettings/EditorBuildSettings.asset" <<'ASSET'
EditorBuildSettings:
  m_Scenes:
  - enabled: 1
    path: Assets/Scenes/Main.unity
ASSET
  : > "$DIR/.gitignore"
fi

case "$VARIANT" in
  urp|dirty)
    cat > "$DIR/Packages/manifest.json" <<'JSON'
{
  "dependencies": {
    "com.unity.render-pipelines.universal": "17.0.3",
    "com.unity.inputsystem": "1.8.2",
    "com.cysharp.unitask": "2.5.0",
    "jp.hadashikick.vcontainer": "1.16.0"
  }
}
JSON
    if [ "$VARIANT" = urp ]; then
      # First-party VContainer use. Without a single .cs file the urp fixture had CS_FILE_COUNT 0,
      # so the generator took the greenfield early exit and the manifest was never consulted —
      # manifest_has(), present(), the `manifest-only` third state and the "binds in full" branch
      # all had zero coverage while the urp test case looked like it was testing them.
      #
      # This yields exactly the interesting mix: VContainer `yes` (manifest + source), UniTask
      # `manifest-only` (manifest, no source), MessagePipe `no`. Do not add UniTask or MessagePipe
      # usage here — the `manifest-only` state has no other fixture.
      cat > "$DIR/Assets/Scripts/GameLifetimeScope.cs" <<'CS'
using VContainer;
using VContainer.Unity;

public sealed class GameLifetimeScope : LifetimeScope
{
    protected override void Configure(IContainerBuilder builder)
    {
        builder.Register<object>(Lifetime.Singleton);
    }
}
CS
    fi
    ;;
  hdrp|both)
    # The pipeline line is the ONLY axis these two vary. Everything else — the Unity version, the
    # asmdef, the scene, the Input System and VContainer packages, the one first-party .cs file — is
    # held identical to `urp` on purpose, so a verdict that differs between `urp`, `hdrp` and `both`
    # can only have come from the pipeline packages. A fixture that varied two things at once could
    # not carry that inference.
    #
    # Deliberately NO com.cysharp.unitask here. The `urp` fixture is the only one that reaches the
    # generator's `manifest-only` stack state (UniTask in the manifest, absent from source), and its
    # own comment says so; giving these two the same mix would quietly make that note false.
    if [ "$VARIANT" = both ]; then
      # Real, and more common than it sounds: a project renders with one pipeline and carries the
      # other because a sample, an asset-store package or a half-finished migration pulled it in.
      # Which one actually renders is recorded in ProjectSettings/GraphicsSettings.asset, which
      # nothing in this repository reads — so `both` is exactly the case where package presence
      # cannot answer the question, and the detector says so rather than guessing.
      PIPELINE_DEPS='    "com.unity.render-pipelines.universal": "17.0.3",
    "com.unity.render-pipelines.high-definition": "17.0.3",'
    else
      PIPELINE_DEPS='    "com.unity.render-pipelines.high-definition": "17.0.3",'
    fi
    # Unquoted heredoc delimiter, because $PIPELINE_DEPS must expand. Nothing else in the body is
    # $-bearing, so there is nothing else to escape.
    cat > "$DIR/Packages/manifest.json" <<JSON
{
  "dependencies": {
$PIPELINE_DEPS
    "com.unity.inputsystem": "1.8.2",
    "jp.hadashikick.vcontainer": "1.16.0"
  }
}
JSON
    # Same first-party VContainer use the urp fixture carries, for the same reason: with zero .cs
    # files the generator takes its greenfield early exit and never consults the manifest, so the
    # stack-detection half of the document would be untested here too.
    cat > "$DIR/Assets/Scripts/GameLifetimeScope.cs" <<'CS'
using VContainer;
using VContainer.Unity;

public sealed class GameLifetimeScope : LifetimeScope
{
    protected override void Configure(IContainerBuilder builder)
    {
        builder.Register<object>(Lifetime.Singleton);
    }
}
CS
    ;;
  builtin)
    cat > "$DIR/Packages/manifest.json" <<'JSON'
{
  "dependencies": {
    "com.unity.ugui": "2.0.0"
  }
}
JSON
    ;;
  legacy)
    cat > "$DIR/Packages/manifest.json" <<'JSON'
{
  "dependencies": {
    "com.unity.render-pipelines.universal": "17.0.3",
    "com.unity.inputsystem": "1.8.2"
  }
}
JSON
    # First-party code that uses coroutines and none of the mandated stack. Two files, because
    # a single file cannot distinguish "counted once" from "counted per match".
    cat > "$DIR/Assets/Scripts/Spawner.cs" <<'CS'
using System.Collections;
using UnityEngine;

public class Spawner : MonoBehaviour
{
    private void Start() { StartCoroutine(SpawnLoop()); }
    private IEnumerator SpawnLoop() { yield return new WaitForSeconds(1f); }
}
CS
    cat > "$DIR/Assets/Scripts/Fader.cs" <<'CS'
using System.Collections;
using UnityEngine;

public class Fader : MonoBehaviour
{
    private void OnEnable() { StartCoroutine(Fade()); }
    private IEnumerator Fade() { yield return null; }
}
CS
    # An ordinary script matching NONE of the four scanned symbols. This is the common case on a
    # real project — most .cs files mention neither VContainer, MessagePipe, UniTask nor
    # StartCoroutine — and it is the case the fixture did not previously contain. Its absence let
    # a `grep | sort | tr` assignment whose grep exits 1 under `set -euo pipefail` kill the
    # generator on every real project while the whole suite stayed green. Do not remove it, and do
    # not add any of the four symbols to it.
    cat > "$DIR/Assets/Scripts/Plain.cs" <<'CS'
using UnityEngine;

public class Plain : MonoBehaviour
{
    private void Update() { }
}
CS
    # Vendored code that DOES reference the stack. If detection counts this, it reports every
    # project as using VContainer, which is the failure this fixture exists to catch.
    mkdir -p "$DIR/Assets/Extensions/SomeVendor"
    cat > "$DIR/Assets/Extensions/SomeVendor/VendorThing.cs" <<'CS'
using VContainer;
using Cysharp.Threading.Tasks;

public class VendorThing
{
    // The literal string "UniTask" is deliberate, not decoration: detection greps for it, and
    // this member is what lets this file also guard the pruning of the UniTask count, not just
    // VContainer's. Do not "clean up" this to a bare using-directive.
    private UniTask _pending;
}
CS
    ;;
  async-mixed)
    cat > "$DIR/Packages/manifest.json" <<'JSON'
{
  "dependencies": {
    "com.unity.render-pipelines.universal": "17.0.3",
    "com.cysharp.unitask": "2.5.0"
  }
}
JSON
    # One file NAMES UniTask without using it — a documentation spec, which is exactly the
    # shape that misled the generator on the first real project it met — against two that
    # genuinely use coroutines. A single reference must not outvote a pattern.
    cat > "$DIR/Assets/Scripts/DocMapSpec.cs" <<'CS'
using NUnit.Framework;

public class DocMapSpec
{
    // Mentions UniTask in an assertion string; does not use it.
    [Test] public void DocsNameTheAsyncLibrary() { Assert.IsTrue("UniTask".Length > 0); }
}
CS
    cat > "$DIR/Assets/Scripts/Blinker.cs" <<'CS'
using System.Collections;
using UnityEngine;

public class Blinker : MonoBehaviour
{
    private void Start() { StartCoroutine(Blink()); }
    private IEnumerator Blink() { yield return new WaitForSeconds(0.2f); }
}
CS
    cat > "$DIR/Assets/Scripts/Pulser.cs" <<'CS'
using System.Collections;
using UnityEngine;

public class Pulser : MonoBehaviour
{
    private void OnEnable() { StartCoroutine(Pulse()); }
    private IEnumerator Pulse() { yield return null; }
}
CS
    ;;
  asmref)
    # WHY THIS VARIANT EXISTS. scripts/validate-asmdefs.sh had a coverage check that read `.asmdef`
    # files and had never heard of `.asmref` — `grep -rn asmref` over the whole toolkit returned
    # nothing on 2026-08-14. Measured on a real shipping project (12 .asmdef, 29 .asmref) it emitted
    # 21 warnings naming 800 files, every one of them false. It survived every prior suite run for
    # one reason only: no fixture here contained an `.asmref`. The fixture set, not the code, was
    # what made the defect invisible — the same lesson `hdrp`/`both` record above.
    #
    # Every path below is a discriminator, not decoration. Do not "tidy" any of them away:
    #
    #   name form      Assets/World Level/     -> {"reference":"Game.Gameplay"}
    #   GUID form      Assets/Extras/          -> {"reference":"GUID:<the asmdef.meta guid>"}
    #                  Both forms occur in the wild and on the measured project the GUID form
    #                  outnumbered the name form more than 2:1, so a fixture carrying one form
    #                  cannot stand in for the other.
    #   spaces         "World Level", "DNA Forms" are transcribed from that project's real folder
    #                  names. An unquoted `for f in $(find …)` splits them and silently reads two
    #                  paths that do not exist; this already broke one probe while the finding was
    #                  being gathered.
    #   dangling x2    Assets/Dangling/ (GUID) and Assets/DanglingName/ (name). An unresolvable
    #                  reference is a real condition and must be REPORTED, not skipped — one per
    #                  form, because a resolver can fail on one and not the other.
    #   true positive  Assets/Loose/Uncovered.cs sits under no assembly file at all. If a "fix"
    #                  suppresses the false warnings by suppressing the check, this file stops being
    #                  named and the guard goes red. A coverage count that falls to zero because the
    #                  sweep died looks exactly like one that falls because the fix worked; this file
    #                  is what tells them apart.
    #   prefix trap    Assets/World LevelExtra/ is a sibling whose name has "World Level" as a
    #                  prefix. The coverage test was a bare `[[ $dir == $covered* ]]`, which reads
    #                  this as covered — latent while only .asmdef directories were listed, live the
    #                  moment .asmref directories joined them. The measured project has exactly this
    #                  pair (Assets/Player and Assets/PlayerPrefsEditor).
    #
    # Assets/Scripts/Gameplay.asmdef ("Game.Gameplay") comes from the shared non-bare block above;
    # this arm adds the .meta that carries its guid, which is what a GUID-form .asmref resolves
    # against. The guid lives in the .meta file, never inside the .asmdef itself.
    cat > "$DIR/Packages/manifest.json" <<'JSON'
{
  "dependencies": {
    "com.unity.render-pipelines.universal": "17.0.3"
  }
}
JSON
    cat > "$DIR/Assets/Scripts/Gameplay.asmdef.meta" <<'META'
fileFormatVersion: 2
guid: 1a2b3c4d5e6f70819a2b3c4d5e6f7081
AssemblyDefinitionImporter:
  externalObjects: {}
  userData:
  assetBundleName:
  assetBundleVariant:
META
    printf 'public sealed class Covered { }\n' > "$DIR/Assets/Scripts/Covered.cs"

    mkdir -p "$DIR/Assets/World Level"
    printf '{"reference":"Game.Gameplay"}\n' > "$DIR/Assets/World Level/Game.Gameplay.asmref"
    printf 'public sealed class LevelThing { }\n' > "$DIR/Assets/World Level/LevelThing.cs"

    mkdir -p "$DIR/Assets/Extras/DNA Forms"
    printf '{"reference":"GUID:1a2b3c4d5e6f70819a2b3c4d5e6f7081"}\n' > "$DIR/Assets/Extras/Vendor.asmref"
    printf 'public sealed class VendorThing { }\n' > "$DIR/Assets/Extras/DNA Forms/VendorThing.cs"

    mkdir -p "$DIR/Assets/Dangling"
    printf '{"reference":"GUID:deadbeefdeadbeefdeadbeefdeadbeef"}\n' > "$DIR/Assets/Dangling/Broken.asmref"
    printf 'public sealed class Orphan { }\n' > "$DIR/Assets/Dangling/Orphan.cs"

    mkdir -p "$DIR/Assets/DanglingName"
    printf '{"reference":"Game.NoSuchAssembly"}\n' > "$DIR/Assets/DanglingName/BrokenName.asmref"
    printf 'public sealed class OrphanName { }\n' > "$DIR/Assets/DanglingName/OrphanName.cs"

    mkdir -p "$DIR/Assets/World LevelExtra"
    printf 'public sealed class Sibling { }\n' > "$DIR/Assets/World LevelExtra/Sibling.cs"

    mkdir -p "$DIR/Assets/Loose"
    printf 'public sealed class Uncovered { }\n' > "$DIR/Assets/Loose/Uncovered.cs"
    ;;
  bare) ;;
  *) echo "err: unknown variant $VARIANT" >&2; exit 2 ;;
esac

if [ "$VARIANT" = dirty ]; then
  # A CLAUDE.md the user wrote by hand, and a .claude/ with no receipt — i.e. not ours.
  printf '# My Game\n\nSENTINEL-DO-NOT-LOSE-ME\n' > "$DIR/CLAUDE.md"
  mkdir -p "$DIR/.claude/agents"
  printf -- '---\nname: theirs\n---\nsomeone else\n' > "$DIR/.claude/agents/theirs.md"
fi

echo "$DIR"
