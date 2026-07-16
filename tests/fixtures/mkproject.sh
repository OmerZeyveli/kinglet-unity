#!/usr/bin/env bash
#
# mkproject.sh — build a synthetic Unity project to test the installer against.
#
# This repo is not a Unity project, and install.sh gates on Assets/ + ProjectSettings/. Everything
# the installer scans is plain text, so a directory with the right shape exercises it fully.
#
# Usage:
#   ./tests/fixtures/mkproject.sh <dir> [--variant urp|builtin|bare|dirty]
#
#   urp      (default) URP + Input System + UniTask + VContainer, one asmdef, one scene
#   builtin  Built-in pipeline, minimal packages
#   bare     No Packages/, no .gitignore, no scenes — the "nothing to detect" path
#   dirty    urp + a pre-existing CLAUDE.md and .claude/, for the upgrade/guard paths
#
set -euo pipefail

DIR="${1:-}"; shift || true
[ -n "$DIR" ] || { echo "usage: mkproject.sh <dir> [--variant urp|builtin|bare|dirty]" >&2; exit 2; }

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
