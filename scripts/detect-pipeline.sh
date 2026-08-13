#!/usr/bin/env bash
#
# detect-pipeline.sh — the one render-pipeline detector.
#
# Usage:
#   ./scripts/detect-pipeline.sh [project-dir]     # default: .
#
# Prints exactly one token on stdout, with a trailing newline:
#
#   builtin    no Packages/manifest.json, or neither pipeline package in it
#   urp        the URP package only
#   hdrp       the HDRP package only
#   urp+hdrp   BOTH packages present
#
# Exits 0 for all four. Exits 2 only on a usage error — an unknown option, or a
# project directory that does not exist. Callers map the token to their own
# display string; this script emits no prose and nothing on stdout but the token.
#
# WHY THIS FILE EXISTS. install.sh and scripts/generate-claude-md.sh each carried
# their own copy of this detection and the two DISAGREED. install.sh ran two
# unconditional greps with HDRP last, so HDRP won; generate-claude-md.sh used
# if/elif with URP first, so URP won. One install of a project carrying both
# packages therefore printed `HDRP` on the console and wrote `URP` into the
# project's own CLAUDE.md — and routed the urp-pipeline skill off the second
# answer. Neither had a both-present state at all: each invented a precedence
# rule by accident of control flow, and the two accidents pointed opposite ways.
#
# ── WHAT THIS SCRIPT DOES NOT DO ─────────────────────────────────────────────
#
# It reports which pipeline PACKAGES ARE PRESENT. That is evidence, not the
# answer. The question a caller usually wants answered is "which pipeline is
# ACTIVE", and this script does not answer it.
#
# Unity records the active pipeline in ProjectSettings/GraphicsSettings.asset, as
# a GUID reference to a render-pipeline asset. Resolving it means finding the
# .asset that GUID names (a .meta lookup across the whole project), opening it,
# and reading the script reference inside — two more file formats and a
# project-wide search, in bash. That is deliberately out of scope, per the
# design's D3, on the ground that a wrong answer is worse than an honest
# "both are installed". This is the honest "both are installed".
#
# So the three claims this script can and cannot support:
#
#   builtin   RELIABLE. Unity cannot render with a pipeline whose package is
#             absent, so "neither package" does mean Built-in.
#   urp/hdrp  SOUND INFERENCE, not proof. A project can carry URP for one
#             imported sample and render with Built-in. Package presence cannot
#             see that.
#   urp+hdrp  EXPLICITLY UNDECIDED. Both are installed; which one renders is
#             not knowable from the manifest, and this script does not guess.
#
# Three more blind spots, named so a caller does not over-read the token:
#
#   - It greps the manifest as TEXT. A package listed in a comment, in
#     "testables", or behind a scoped registry counts as present; a pipeline
#     supplied some other way (a local package under Packages/, a git URL whose
#     text does not carry the package id) counts as absent.
#   - It reads only Packages/manifest.json. Packages/packages-lock.json,
#     Library/, and every ProjectSettings/ file are unread.
#   - It says nothing about VERSION. URP 12 and URP 17 are both `urp` here.

set -euo pipefail

usage() {
  sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

PROJECT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage ;;
    -*)        printf 'detect-pipeline.sh: unknown option: %s\n' "$1" >&2; exit 2 ;;
    *)         PROJECT_DIR="$1"; shift ;;
  esac
done
PROJECT_DIR="${PROJECT_DIR:-.}"
[ -d "$PROJECT_DIR" ] || {
  printf 'detect-pipeline.sh: not a directory: %s\n' "$PROJECT_DIR" >&2
  exit 2
}

MANIFEST="$PROJECT_DIR/Packages/manifest.json"

# `if grep -q`, not `grep -q ... && HAS=1`. The && form is the shape
# generate-claude-md.sh already documents against: as the last command of a
# function or of an && list it returns 1 when the test fails, and under `set -e`
# that ends the script. `grep -q` on a FILE ARGUMENT is safe — the SIGPIPE trap
# that `grep -q` is famous for needs a pipe, and there is none here.
HAS_URP=0
HAS_HDRP=0
if [ -f "$MANIFEST" ]; then
  if grep -q 'com.unity.render-pipelines.universal' "$MANIFEST"; then HAS_URP=1; fi
  if grep -q 'com.unity.render-pipelines.high-definition' "$MANIFEST"; then HAS_HDRP=1; fi
fi

if [ "$HAS_URP" -eq 1 ] && [ "$HAS_HDRP" -eq 1 ]; then
  printf 'urp+hdrp\n'
elif [ "$HAS_URP" -eq 1 ]; then
  printf 'urp\n'
elif [ "$HAS_HDRP" -eq 1 ]; then
  printf 'hdrp\n'
else
  printf 'builtin\n'
fi
