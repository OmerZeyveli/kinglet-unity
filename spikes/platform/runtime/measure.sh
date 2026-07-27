#!/usr/bin/env bash
# measure.sh — collect performance measurements for one packaged host-probe artifact.
#
# Native POSIX hosts only: Linux and Darwin (macOS). Windows uses measure.ps1.
#
# Emits a single JSON object to stdout:
#   {"cold_start_ms":[<30 ints>],"peak_rss_kb":<int>,"artifact_bytes":<int>,"dependency_count":<int>}
#
# Cold-start: 30 wall-clock samples of the version invocation, in integer milliseconds.
# Peak RSS:   Maximum resident set size in KILOBYTES on every platform.
#             Linux  — /usr/bin/time -v reports kbytes already.
#             Darwin — /usr/bin/time -l reports BYTES; divided by 1024 here.
#             Getting that divide wrong makes macOS look 1024x worse than Linux and
#             nothing downstream would notice, so it is asserted by a test.
# Artifact:   file size in bytes.
#
# Usage:
#   measure.sh <exe> <dependency_count> <version_arg>
#     <exe>               path to the packaged artifact
#     <dependency_count>  integer supplied by the caller (per-candidate lockfile count)
#     <version_arg>       the argument that triggers a version print:
#                         "--version" (go/rust/dotnet) or "version" (python)
#
# Library mode: `KINGLET_MEASURE_LIB=1 . measure.sh` defines the functions and returns
# without measuring anything, so the Darwin-only parsing can be exercised on Linux.
#
# Shell conventions (repo CLAUDE.md): bash, set -euo pipefail, no bash-4 associative
# arrays, no GNU-only grep perl-regex, and no early-exit pipe under set -e
# (SIGPIPE 141 becomes a failure). See tests for the enforced literals.
set -euo pipefail

KINGLET_MEASURE_LIB="${KINGLET_MEASURE_LIB:-0}"

# --- Pure helpers -----------------------------------------------------------

# rss_kb_from_time_v_output — parse GNU /usr/bin/time -v stderr.
# The value is already in kbytes, so it is used as-is.
rss_kb_from_time_v_output() {
  # Read the whole text with awk (no `head` pipe under set -e).
  printf '%s\n' "$1" \
    | awk -F': ' '/Maximum resident set size \(kbytes\)/ {print $2; found=1} END {if (!found) print 0}'
}

# rss_kb_from_time_l_output — parse BSD /usr/bin/time -l stderr.
# BSD reports "  12345678  maximum resident set size" in BYTES; convert to kbytes.
rss_kb_from_time_l_output() {
  printf '%s\n' "$1" \
    | awk '/maximum resident set size/ {print int($1 / 1024); found=1} END {if (!found) print 0}'
}

# rss_kb_from_output <platform> <text>
rss_kb_from_output() {
  case "$1" in
    Linux)  rss_kb_from_time_v_output "$2" ;;
    Darwin) rss_kb_from_time_l_output "$2" ;;
    *)      echo 0 ;;
  esac
}

# time_flag_for <platform> — the /usr/bin/time flag that reports peak RSS.
time_flag_for() {
  case "$1" in
    Linux)  echo "-v" ;;
    Darwin) echo "-l" ;;
    *)      echo "unsupported" ;;
  esac
}

# now_ms_mode_for <platform> — how to read a millisecond clock.
#   date  — GNU date supports %3N (Linux).
#   perl  — BSD date has no sub-second format; macOS ships perl with Time::HiRes.
#   python — fallback if perl is absent.
now_ms_mode_for() {
  case "$1" in
    Linux)
      echo "date"
      ;;
    Darwin)
      if command -v perl > /dev/null 2>&1; then
        echo "perl"
      else
        echo "python"
      fi
      ;;
    *)
      echo "unsupported"
      ;;
  esac
}

# now_ms <mode> — integer milliseconds since the epoch.
now_ms() {
  case "$1" in
    date)
      date +%s%3N
      ;;
    perl)
      perl -MTime::HiRes=time -e 'printf("%d\n", time() * 1000)'
      ;;
    python)
      python3 -c 'import time; print(int(time.time() * 1000))'
      ;;
    *)
      echo "measure.sh: no millisecond clock for mode: $1" >&2
      return 1
      ;;
  esac
}

if [ "$KINGLET_MEASURE_LIB" = "1" ]; then
  return 0 2> /dev/null || exit 0
fi

# --- Main -------------------------------------------------------------------

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

platform=$(uname -s)
time_flag=$(time_flag_for "$platform")
now_ms_mode=$(now_ms_mode_for "$platform")
if [ "$time_flag" = "unsupported" ] || [ "$now_ms_mode" = "unsupported" ]; then
  echo "measure.sh: unsupported platform: $platform (accept only Darwin or Linux)" >&2
  exit 2
fi

# --- Cold-start: 30 wall-clock samples in integer milliseconds ---
sample_count=30
samples=""
i=0
while [ "$i" -lt "$sample_count" ]; do
  t0=$(now_ms "$now_ms_mode")
  "$exe" "$version_arg" > /dev/null 2>&1 || true
  t1=$(now_ms "$now_ms_mode")
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

# --- Peak RSS: /usr/bin/time -v (Linux, kbytes) or -l (Darwin, bytes) ---
time_output=$(/usr/bin/time "$time_flag" "$exe" "$version_arg" 2>&1 1>/dev/null || true)
peak_rss_kb=$(rss_kb_from_output "$platform" "$time_output")
if [ -z "$peak_rss_kb" ]; then
  peak_rss_kb=0
fi

# --- Artifact size in bytes ---
artifact_bytes=$(wc -c < "$exe")
artifact_bytes=$(printf '%s' "$artifact_bytes" | tr -d '[:space:]')

# --- Emit JSON ---
printf '{"cold_start_ms":[%s],"peak_rss_kb":%s,"artifact_bytes":%s,"dependency_count":%s}\n' \
  "$samples" "$peak_rss_kb" "$artifact_bytes" "$dep_count"
