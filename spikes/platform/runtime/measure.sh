#!/usr/bin/env bash
# measure.sh — collect performance measurements for one packaged host-probe artifact.
#
# Emits a single JSON object to stdout:
#   {"cold_start_ms":[<30 ints>],"peak_rss_kb":<int>,"artifact_bytes":<int>,"dependency_count":<int>}
#
# Cold-start: 30 wall-clock samples of the version invocation, in integer milliseconds.
# Peak RSS:   Maximum resident set size (kbytes) via /usr/bin/time -v.
# Artifact:   file size in bytes.
#
# Usage:
#   measure.sh <exe> <dependency_count> <version_arg>
#     <exe>               path to the packaged artifact
#     <dependency_count>  integer supplied by the caller (per-candidate lockfile count)
#     <version_arg>       the argument that triggers a version print:
#                         "--version" (go/rust/dotnet) or "version" (python)
#
# Shell conventions (repo CLAUDE.md): bash, set -euo pipefail, no bash-4 associative
# arrays, no GNU-only grep perl-regex, and no early-exit pipe under set -e
# (SIGPIPE 141 becomes a failure). See tests for the enforced literals.
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: measure.sh <exe> <dependency_count> <version_arg>" >&2
  exit 2
fi

exe="$1"
dep_count="$2"
version_arg="$3"

if [ ! -x "$exe" ]; then
  echo "measure.sh: not an executable: $exe" >&2
  exit 2
fi

# --- Cold-start: 30 wall-clock samples in integer milliseconds ---
sample_count=30
samples=""
i=0
while [ "$i" -lt "$sample_count" ]; do
  t0=$(date +%s%3N)
  "$exe" "$version_arg" > /dev/null 2>&1 || true
  t1=$(date +%s%3N)
  ms=$((t1 - t0))
  # Guard against a zero/negative reading on a very fast native binary: the
  # cold-start measurement schema requires positive integers.
  if [ "$ms" -lt 1 ]; then
    ms=1
  fi
  if [ -z "$samples" ]; then
    samples="$ms"
  else
    samples="$samples,$ms"
  fi
  i=$((i + 1))
done

# --- Peak RSS via /usr/bin/time -v ---
# Read the whole stderr with awk (no `head` pipe under set -e).
time_output=$(/usr/bin/time -v "$exe" "$version_arg" 2>&1 1>/dev/null || true)
peak_rss_kb=$(printf '%s\n' "$time_output" \
  | awk -F': ' '/Maximum resident set size \(kbytes\)/ {print $2; found=1} END {if (!found) print 0}')
if [ -z "$peak_rss_kb" ]; then
  peak_rss_kb=0
fi

# --- Artifact size in bytes ---
artifact_bytes=$(wc -c < "$exe")
artifact_bytes=$(printf '%s' "$artifact_bytes" | tr -d '[:space:]')

# --- Emit JSON ---
printf '{"cold_start_ms":[%s],"peak_rss_kb":%s,"artifact_bytes":%s,"dependency_count":%s}\n' \
  "$samples" "$peak_rss_kb" "$artifact_bytes" "$dep_count"
