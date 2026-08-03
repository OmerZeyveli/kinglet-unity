#!/usr/bin/env bash
#
# mkproject.sh — build a synthetic Unity project to test the installer against.
#
# This repo is not a Unity project, and install.sh gates on Assets/ + ProjectSettings/. Everything
# the installer scans is plain text, so a directory with the right shape exercises it fully.
#
# Usage:
#   ./tests/fixtures/mkproject.sh <dir> [--variant urp|builtin|bare|dirty|legacy]
#
#   urp      (default) URP + Input System + UniTask + VContainer, one asmdef, one scene
#   builtin  Built-in pipeline, minimal packages
#   bare     No Packages/, no .gitignore, no scenes — the "nothing to detect" path
#   dirty    urp + a pre-existing CLAUDE.md and .claude/, for the upgrade/guard paths
#   legacy   URP, no VContainer/MessagePipe/UniTask, coroutine-using scripts — the "does not bind" path
#
set -euo pipefail

DIR="${1:-}"; shift || true
[ -n "$DIR" ] || { echo "usage: mkproject.sh <dir> [--variant urp|builtin|bare|dirty|legacy]" >&2; exit 2; }

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
