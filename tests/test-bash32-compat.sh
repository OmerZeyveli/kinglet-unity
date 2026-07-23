#!/usr/bin/env bash
# Regression gate for scripts that run under macOS's system Bash 3.2.

set -euo pipefail

BASH4_ASSOCIATIVE_ARRAYS=$(
    grep -lE '(^|[[:space:]])declare[[:space:]]+-A([[:space:]]|$)' \
        "$REPO_DIR"/.claude/hooks/*.sh || true
)

assert_eq \
    "" \
    "$BASH4_ASSOCIATIVE_ARRAYS" \
    "hook scripts avoid Bash 4 associative arrays"
