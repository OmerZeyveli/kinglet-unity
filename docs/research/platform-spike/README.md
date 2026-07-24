# Kinglet Platform Spike Evidence

This directory contains the sanitized, reviewable evidence accepted by the maintainer-only spike
harness. It does not contain raw client transcripts, credentials, prompts, machine paths, or local
binary captures.

## Storage boundary

- Raw runs live at `.kinglet/local/spikes/<run-id>/` and are ignored by Git.
- A raw run places its sanitized publication subset below `<run-dir>/publish/`.
- Accepted records live at `docs/research/platform-spike/evidence/`.
- Small sanitized text artifacts live at `docs/research/platform-spike/artifacts/`.
- Deterministic coverage outputs live at `docs/research/platform-spike/reports/`.

Version 1 commits only small UTF-8 JSON, XML, plain-text, and Markdown artifacts required to review
a claim. Executables, screenshots, binary logs, and large diagnostics remain local; committed
evidence records their checksum and reproducible command instead.

## Maintainer commands

```bash
python3 -m tools.kinglet_spike validate <record.json> --repo-root <path>
python3 -m tools.kinglet_spike publish <record.json> --repo-root <path>
python3 -m tools.kinglet_spike report --repo-root <path> --matrix <matrix.json>
python3 -m tools.kinglet_spike gate <0A|0R|0C:client|0U|0D> --repo-root <path>
```

Publication is immutable. A retry uses a new run ID and new artifact paths; it never overwrites or
deletes a previous result, including a failed or inconclusive result.

## Safety rules

Committed records and artifacts must not contain credentials, account identifiers, raw prompts,
absolute user paths, path traversal, or symlink escapes. Prompt evidence consists only of a
synthetic prompt ID and lowercase SHA-256 digest. If sanitization cannot prove an artifact safe, it
stays local and the result remains inconclusive.

## Reviewer sequence

1. Inspect the canonical evidence record and its environment, command, assertions, and status.
2. Verify every published artifact checksum against the record.
3. Regenerate `coverage.json` and `coverage.md` from the fixed matrix.
4. Evaluate the relevant gate and confirm every non-pass state remains visible.

Manual prose may interpret evidence, but it cannot change a record status or close a matrix cell.
Missing Windows evidence therefore remains `missing` until a native Windows run is published.
