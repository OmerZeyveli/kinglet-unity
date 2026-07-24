# Codebase Memory Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run a reproducible, safety-bounded comparison of normal Codex exploration against Codex plus pinned Codebase Memory, then make independent evidence-based decisions about using it for Kinglet development and supporting it as an optional external provider.

**Architecture:** A standard-library Python harness strictly loads preregistered tasks, launches paired ephemeral Codex processes against immutable target snapshots, parses exact Codex token telemetry, scores structured answers against source-derived facts, and renders sanitized deterministic reports. The pinned upstream binary is built and tested in an ignored detached worktree, indexes only explicitly allowed roots into run-local caches, and is exposed to treatment runs only through the read-only `analysis` MCP profile.

**Tech Stack:** Python 3 standard library, `unittest`, Bash, JSON/JSONL, Markdown, Codex CLI 0.145.0 or the exact version recorded at execution, pinned C source build, Git worktrees, SHA-256.

## Global Constraints

- Follow `docs/superpowers/specs/2026-07-24-codebase-memory-evaluation-design.md`.
- The experiment candidate is exactly `97ce23f9827177fff3858831156e9795c6832b18`; a different revision requires a new candidate ID and report.
- The Kinglet target is exactly `a49916b77900e87fcbaf226f332f5923faf7dc28`.
- The Unity/C# target is exactly `bd72241ab91c664176091789c9408d676783abec`.
- Never run upstream `install`, `update`, or `uninstall` commands.
- Never build the UI, write global Codex configuration, install upstream skills or agents, or enable upstream hooks.
- Index creation is a one-shot maintainer action. Treatment MCP servers run only with `--tool-profile=analysis`.
- Both Codex arms inherit the same existing user configuration so Superpowers remains available; only the treatment arm receives the ephemeral MCP override.
- Every Codex process uses an immutable target worktree, `--ephemeral`, `--json`, `--sandbox read-only`, one pinned model, one pinned reasoning effort, and one structured answer schema.
- Raw event streams, prompts, absolute paths, caches, and local diagnostics stay under `.kinglet/local/experiments/codebase-memory/`.
- Only sanitized, repository-relative, deterministic results are committed under `docs/research/codebase-memory/`.
- Exact Codex usage telemetry is mandatory. Character counts, byte counts, or estimated tokens cannot close the token gate.
- Infrastructure failure is not a task failure and is never silently retried into a valid repetition.
- Windows and macOS remain untested; this experiment cannot close 0R, 0C, 0U, or 0D.
- Use only the Python standard library in the Kinglet harness.
- JSON output uses UTF-8, LF, sorted keys, deterministic list ordering, and a final newline.
- Every implementation task follows red-green-refactor and ends with its own commit.

---

## File map

| Path | Responsibility |
| --- | --- |
| `tools/kinglet_cbm_eval/model.py` | Frozen candidate, task, answer, run, score, and decision types |
| `tools/kinglet_cbm_eval/load.py` | Strict versioned JSON loading and unknown-field rejection |
| `tools/kinglet_cbm_eval/codex_events.py` | Structured answer and exact Codex JSONL telemetry parsing |
| `tools/kinglet_cbm_eval/score.py` | Mechanistic fact scoring, paired metrics, pilot stops, and final gates |
| `tools/kinglet_cbm_eval/process.py` | Bounded process groups, cleanup, environment construction, and global-file snapshots |
| `tools/kinglet_cbm_eval/candidate.py` | Candidate provenance, one-shot indexing, analysis-tool probe, and readiness receipts |
| `tools/kinglet_cbm_eval/runner.py` | Fixed schedules and baseline/treatment Codex command construction |
| `tools/kinglet_cbm_eval/report.py` | Sanitized deterministic JSON and Markdown reports |
| `tools/kinglet_cbm_eval/cli.py` | `validate`, `readiness`, `probe`, `schedule`, `run`, `score`, and `report` commands |
| `spikes/evaluations/codebase-memory/candidate-v1.json` | Pinned upstream and target identities plus execution policy |
| `spikes/evaluations/codebase-memory/tasks-v1.json` | Eight preregistered prompts and source-derived scoring rules |
| `spikes/evaluations/codebase-memory/answer-v1.schema.json` | Structured Codex answer contract |
| `tests/kinglet_cbm_eval/` | Unit and integration-contract tests |
| `tests/test-kinglet-cbm-eval.sh` | Existing Bash runner bridge |
| `docs/research/codebase-memory/README.md` | Reproduction, safety, and interpretation guide |
| `docs/research/codebase-memory/report.json` | Sanitized machine-readable outcome |
| `docs/research/codebase-memory/report.md` | Human-readable findings and both decisions |

## Stable interfaces

```python
class EvaluationError(ValueError):
    code: str
    detail: str

@dataclass(frozen=True)
class CandidateConfig:
    schema: str
    id: str
    repository: str
    commit: str
    source_path: str
    binary_path: str
    tool_profile: Literal["analysis"]
    license_spdx: Literal["MIT"]
    license_path: str
    bundle_policy: Literal["external-only"]
    kinglet_commit: str
    unity_commit: str
    model: str
    reasoning_effort: str
    codex_version: str
    timeout_seconds: int
    random_seed: int

@dataclass(frozen=True)
class EvidenceRef:
    path: str
    symbol: str

@dataclass(frozen=True)
class FactRule:
    id: str
    weight: int
    critical: bool
    claim_any: tuple[str, ...]
    evidence_any: tuple[tuple[EvidenceRef, ...], ...]

@dataclass(frozen=True)
class EvaluationTask:
    id: str
    target: Literal["kinglet", "unity-mcp"]
    target_commit: str
    category: Literal["structural", "literal", "coverage"]
    prompt: str
    facts: tuple[FactRule, ...]
    forbidden_claims: tuple[str, ...]
    pilot: bool

@dataclass(frozen=True)
class TokenUsage:
    input_tokens: int
    cached_input_tokens: int
    output_tokens: int

    @property
    def total_tokens(self) -> int:
        return self.input_tokens + self.output_tokens

@dataclass(frozen=True)
class AnswerFinding:
    claim: str
    evidence: tuple[EvidenceRef, ...]

@dataclass(frozen=True)
class EvaluationAnswer:
    schema: str
    task_id: str
    findings: tuple[AnswerFinding, ...]
    limitations: tuple[str, ...]

@dataclass(frozen=True)
class RunReceipt:
    schema: str
    run_id: str
    task_id: str
    arm: Literal["baseline", "treatment"]
    repetition: int
    target_commit: str
    codex_version: str
    model: str
    reasoning_effort: str
    started_at: str
    ended_at: str
    exit_code: int
    timed_out: bool
    usage: TokenUsage | None
    tool_calls: tuple[str, ...]
    answer: EvaluationAnswer | None
    infrastructure_error: str | None

load_candidate(path: Path) -> CandidateConfig
load_tasks(path: Path) -> tuple[EvaluationTask, ...]
parse_codex_events(path: Path) -> ParsedCodexRun
score_answer(task: EvaluationTask, answer: EvaluationAnswer) -> TaskScore
paired_task_result(receipts: Iterable[RunReceipt], task: EvaluationTask) -> PairedTaskResult
evaluate_decisions(results: Iterable[PairedTaskResult]) -> EvaluationDecisions
run_bounded(command: Sequence[str], *, cwd: Path, env: Mapping[str, str], timeout_seconds: int) -> ProcessResult
render_json(report: EvaluationReport) -> str
render_markdown(report: EvaluationReport) -> str
```

The primary token metric is always:

```python
total_tokens = input_tokens + output_tokens
paired_reduction = 1.0 - (treatment_median_tokens / baseline_median_tokens)
```

`cached_input_tokens` is reported separately and is not added a second time because it is a subset of Codex input accounting.

---

### Task 1: Freeze strict candidate and task contracts

**Files:**
- Create: `tools/kinglet_cbm_eval/__init__.py`
- Create: `tools/kinglet_cbm_eval/model.py`
- Create: `tools/kinglet_cbm_eval/load.py`
- Create: `tests/kinglet_cbm_eval/__init__.py`
- Create: `tests/kinglet_cbm_eval/support.py`
- Test: `tests/kinglet_cbm_eval/test_load.py`

**Interfaces:**
- Accept only `kinglet.cbm-eval.candidate/v1` and `kinglet.cbm-eval.tasks/v1`.
- Reject missing fields, unknown fields, duplicate IDs, invalid regexes, nonpositive weights, non-40-character lowercase commits, absolute evidence paths, traversal, and a corpus other than exactly eight tasks with the approved category counts.

- [ ] **Step 1: Add failing strict-loader tests**

```python
class LoadTasksTests(unittest.TestCase):
    def test_accepts_exact_eight_task_corpus(self):
        tasks = load_tasks(write_tasks(self.root, valid_tasks()))
        self.assertEqual(8, len(tasks))
        self.assertEqual(4, sum(t.target == "kinglet" and t.category == "structural" for t in tasks))
        self.assertEqual(2, sum(t.target == "unity-mcp" and t.category == "structural" for t in tasks))
        self.assertEqual(1, sum(t.category == "literal" for t in tasks))
        self.assertEqual(1, sum(t.category == "coverage" for t in tasks))

    def test_rejects_unknown_nested_fact_field(self):
        value = valid_tasks()
        value["tasks"][0]["facts"][0]["surprise"] = True
        with self.assertRaisesRegex(EvaluationError, r"E_FIELD"):
            load_tasks(write_tasks(self.root, value))

    def test_rejects_absolute_or_traversing_evidence_path(self):
        for unsafe in ("/etc/passwd", "../outside.py", "safe/../../outside.py"):
            value = valid_tasks()
            value["tasks"][0]["facts"][0]["evidence_any"][0][0]["path"] = unsafe
            with self.subTest(unsafe=unsafe), self.assertRaisesRegex(EvaluationError, r"E_PATH"):
                load_tasks(write_tasks(self.root, value))
```

- [ ] **Step 2: Run the focused tests and confirm the red state**

Run:

```bash
python3 -m unittest tests.kinglet_cbm_eval.test_load -v
```

Expected: import failure because `tools.kinglet_cbm_eval` does not exist.

- [ ] **Step 3: Implement frozen models and exact-field decoders**

Use one reusable helper for every object:

```python
def _exact_fields(value: object, required: set[str], *, code: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise EvaluationError(code, "expected object")
    actual = set(value)
    missing = sorted(required - actual)
    unknown = sorted(actual - required)
    if missing:
        raise EvaluationError("E_FIELD", f"missing field: {missing[0]}")
    if unknown:
        raise EvaluationError("E_FIELD", f"unknown field: {unknown[0]}")
    return value
```

`EvaluationError.__str__` must return `"<code>: <detail>"`. Convert JSON arrays to tuples, compile every `claim_any` and `forbidden_claims` regex during load, and enforce the exact corpus mix after decoding.

- [ ] **Step 4: Run loader tests**

Run:

```bash
python3 -m unittest tests.kinglet_cbm_eval.test_load -v
```

Expected: all loader tests pass.

- [ ] **Step 5: Commit**

```bash
git add tools/kinglet_cbm_eval tests/kinglet_cbm_eval
git commit -m "feat: add codebase memory evaluation contracts"
```

---

### Task 2: Parse structured answers and exact Codex telemetry

**Files:**
- Create: `tools/kinglet_cbm_eval/codex_events.py`
- Create: `spikes/evaluations/codebase-memory/answer-v1.schema.json`
- Test: `tests/kinglet_cbm_eval/test_codex_events.py`

**Interfaces:**
- `load_answer(path, expected_task_id) -> EvaluationAnswer`
- `parse_codex_events(path) -> ParsedCodexRun`
- Require exactly one terminal usage object containing nonnegative integer `input_tokens`, `cached_input_tokens`, and `output_tokens`.
- Record MCP tool names from completed tool-call items without treating ordinary shell/read calls as Codebase Memory calls.

- [ ] **Step 1: Add failing answer and JSONL parser tests**

```python
def test_parses_terminal_usage_and_mcp_tools(self):
    events = [
        {"type": "thread.started", "thread_id": "t1"},
        {"type": "item.completed", "item": {
            "type": "mcp_tool_call",
            "server": "codebase-memory-mcp",
            "tool": "search_graph",
            "status": "completed",
        }},
        {"type": "turn.completed", "usage": {
            "input_tokens": 120,
            "cached_input_tokens": 20,
            "output_tokens": 30,
        }},
    ]
    parsed = parse_codex_events(write_jsonl(self.root, events))
    self.assertEqual(150, parsed.usage.total_tokens)
    self.assertEqual(("codebase-memory-mcp.search_graph",), parsed.tool_calls)

def test_rejects_missing_or_ambiguous_usage(self):
    for events in (
        [{"type": "turn.completed"}],
        [
            {"type": "turn.completed", "usage": usage()},
            {"type": "turn.completed", "usage": usage()},
        ],
    ):
        with self.subTest(events=events), self.assertRaisesRegex(EvaluationError, "E_TELEMETRY"):
            parse_codex_events(write_jsonl(self.root, events))
```

- [ ] **Step 2: Run the focused tests and confirm they fail**

Run:

```bash
python3 -m unittest tests.kinglet_cbm_eval.test_codex_events -v
```

Expected: module import failure.

- [ ] **Step 3: Add the exact answer schema**

The schema must set `additionalProperties: false` at every object level and require:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Kinglet Codebase Memory Evaluation Answer v1",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema", "task_id", "findings", "limitations"],
  "properties": {
    "schema": {"const": "kinglet.cbm-eval.answer/v1"},
    "task_id": {"type": "string", "minLength": 1},
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["claim", "evidence"],
        "properties": {
          "claim": {"type": "string", "minLength": 1},
          "evidence": {
            "type": "array",
            "minItems": 1,
            "items": {
              "type": "object",
              "additionalProperties": false,
              "required": ["path", "symbol"],
              "properties": {
                "path": {"type": "string", "minLength": 1},
                "symbol": {"type": "string", "minLength": 1}
              }
            }
          }
        }
      }
    },
    "limitations": {"type": "array", "items": {"type": "string", "minLength": 1}}
  }
}
```

- [ ] **Step 4: Implement line-by-line event parsing**

Decode each nonblank line independently, reject malformed JSON with its line number, collect terminal usage candidates, and normalize only the known Codex 0.145 event shape. Do not guess alternate token field names. Phase 0 will block execution if the installed CLI emits a different shape.

- [ ] **Step 5: Run parser tests and commit**

```bash
python3 -m unittest tests.kinglet_cbm_eval.test_codex_events -v
git add tools/kinglet_cbm_eval/codex_events.py spikes/evaluations/codebase-memory/answer-v1.schema.json tests/kinglet_cbm_eval/test_codex_events.py
git commit -m "feat: parse codex evaluation telemetry"
```

---

### Task 3: Implement deterministic scoring and both decision gates

**Files:**
- Create: `tools/kinglet_cbm_eval/score.py`
- Test: `tests/kinglet_cbm_eval/test_score.py`

**Interfaces:**
- A fact passes only when one `claim_any` regex matches a finding claim and one complete `evidence_any` alternative is present in that same finding.
- Missing a critical fact or matching a forbidden claim produces score `0.0` and a critical failure code.
- Two valid repetitions per arm are required in the full experiment.
- Per-task values use the median of repetitions; the overall value uses the median of eight per-task values.

- [ ] **Step 1: Add failing fact, pairing, and gate tests**

```python
def test_fact_requires_claim_and_complete_evidence_in_same_finding(self):
    task = task_with_fact(
        claim_any=(r"\bloads?\b.*\bvalidates?\b",),
        evidence_any=((ref("tools/x.py", "load"), ref("tools/x.py", "validate")),),
    )
    split = answer(
        finding("loads the record", ref("tools/x.py", "load")),
        finding("validates the record", ref("tools/x.py", "validate")),
    )
    self.assertEqual(0.0, score_answer(task, split).correctness)

def test_development_gate_requires_all_balanced_thresholds(self):
    results = balanced_results(
        treatment_correctness_delta=0.0,
        neutral_or_better=6,
        median_reduction=0.50,
        critical_failures=0,
        coverage_fallback=True,
    )
    self.assertEqual("development-only", evaluate_decisions(results).development)

def test_product_gate_is_independent_and_requires_unity_fallback_evidence(self):
    decisions = evaluate_decisions(balanced_results(product_fallback=False))
    self.assertEqual("development-only", decisions.development)
    self.assertEqual("reject", decisions.product)
```

- [ ] **Step 2: Run the focused test and confirm the red state**

```bash
python3 -m unittest tests.kinglet_cbm_eval.test_score -v
```

- [ ] **Step 3: Implement the exact formulas**

```python
def paired_reduction(baseline_tokens: float, treatment_tokens: float) -> float:
    if baseline_tokens <= 0:
        raise EvaluationError("E_TELEMETRY", "baseline token total must be positive")
    return 1.0 - treatment_tokens / baseline_tokens

def median(values: Sequence[float]) -> float:
    ordered = sorted(values)
    count = len(ordered)
    if count == 0:
        raise EvaluationError("E_REPETITION", "median requires values")
    middle = count // 2
    if count % 2:
        return ordered[middle]
    return (ordered[middle - 1] + ordered[middle]) / 2.0
```

The development gate passes only if all are true:

1. treatment overall correctness is at least baseline overall correctness;
2. no treatment answer has a critical false claim;
3. median of eight per-task paired reductions is at least `0.50`;
4. treatment correctness is neutral or better on at least six of eight tasks;
5. the coverage task explicitly reports source fallback when coverage is incomplete;
6. every readiness boundary assertion passes.

The product gate additionally requires the development gate, no regression on both Unity structural tasks, and passing absent/stale/partial/failure fallback probes. Its passing vocabulary is `optional-provider-candidate`, never `adopted` or `bundled`.

- [ ] **Step 4: Encode pilot stop conditions**

`evaluate_pilot` returns stop when any pilot pair has lower treatment correctness, any critical false claim, incomplete telemetry, boundary failure, stale graph, orphan process, or when all three paired token reductions are negative.

- [ ] **Step 5: Run tests and commit**

```bash
python3 -m unittest tests.kinglet_cbm_eval.test_score -v
git add tools/kinglet_cbm_eval/score.py tests/kinglet_cbm_eval/test_score.py
git commit -m "feat: score codebase memory comparisons"
```

---

### Task 4: Add bounded process execution and global-state guards

**Files:**
- Create: `tools/kinglet_cbm_eval/process.py`
- Test: `tests/kinglet_cbm_eval/test_process.py`

**Interfaces:**
- Never invoke a shell.
- Start every child in a new process group.
- On timeout, terminate the whole group, wait two seconds, then kill the whole group.
- Snapshot content hashes and absence/presence state without copying secrets into receipts.

- [ ] **Step 1: Add failing timeout, environment, and snapshot tests**

```python
def test_timeout_terminates_process_group(self):
    result = run_bounded(
        [sys.executable, "-c", "import time; time.sleep(30)"],
        cwd=self.root,
        env=minimal_env(self.root),
        timeout_seconds=1,
    )
    self.assertTrue(result.timed_out)
    self.assertNotEqual(0, result.exit_code)

def test_snapshot_reports_hash_change_without_content(self):
    target = self.root / "config.toml"
    target.write_text("secret = 'one'\n", encoding="utf-8")
    before = snapshot_paths((target,))
    target.write_text("secret = 'two'\n", encoding="utf-8")
    changed = compare_snapshots(before, snapshot_paths((target,)))
    self.assertEqual((target.as_posix(),), changed)
    self.assertNotIn("secret", repr(before))
```

- [ ] **Step 2: Implement process groups and deterministic capture**

Call `subprocess.Popen` with `command` as its positional argument and the exact keyword arguments `cwd=cwd`, `env=dict(env)`, `shell=False`, `start_new_session=True`, `stdin=DEVNULL`, `stdout=PIPE`, `stderr=PIPE`, and `text=False`. Capture bytes into run-local files, return their SHA-256 values, and decode only for diagnostics with UTF-8 replacement. Never include the parent environment wholesale. The Codex allowlist is `PATH`, `HOME`, `CODEX_HOME`, `LANG`, `LC_ALL`, `SSL_CERT_FILE`, `SSL_CERT_DIR`, `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `NO_PROXY`, and `OPENAI_API_KEY` when each is present, plus explicit `CBM_*` values in treatment only. Pass secret values to the child without writing them into commands, receipts, logs, or reports.

- [ ] **Step 3: Guard the exact global paths**

Snapshot these paths before readiness and after every phase:

```text
~/.codex/config.toml
~/.codex/AGENTS.md
~/.codex/hooks.json
~/.codex/skills/codebase-memory
every entry below ~/.codex/skills whose basename begins with codebase-memory
every entry below ~/.codex/agents whose basename begins with codebase-memory
```

Directories are represented by a deterministic hash of relative entry names, file types, and file hashes. A changed snapshot is a hard boundary failure.

- [ ] **Step 4: Run tests and commit**

```bash
python3 -m unittest tests.kinglet_cbm_eval.test_process -v
git add tools/kinglet_cbm_eval/process.py tests/kinglet_cbm_eval/test_process.py
git commit -m "feat: isolate evaluation processes"
```

---

### Task 5: Build candidate readiness and one-shot index controls

**Files:**
- Create: `tools/kinglet_cbm_eval/candidate.py`
- Test: `tests/kinglet_cbm_eval/test_candidate.py`

**Interfaces:**
- Validate commit, build/test command receipts, compiler identity, executable version, and SHA-256.
- Build a target-specific environment with exactly one `CBM_ALLOWED_ROOT` and one run-local `CBM_CACHE_DIR`.
- Probe MCP `tools/list` and require the exact analysis surface.
- Detect only an explicitly configured executable path; absence or identity mismatch is a clean unavailable result and never triggers installation, update, PATH search, or trust changes.

- [ ] **Step 1: Add failing environment and tool-surface tests**

```python
ANALYSIS_TOOLS = (
    "check_index_coverage",
    "detect_changes",
    "get_architecture",
    "get_code_snippet",
    "get_graph_schema",
    "index_status",
    "list_projects",
    "query_graph",
    "search_code",
    "search_graph",
    "trace_path",
)

def test_analysis_surface_excludes_mutation_tools(self):
    validate_analysis_tools(ANALYSIS_TOOLS)
    with self.assertRaisesRegex(EvaluationError, "E_TOOL_PROFILE"):
        validate_analysis_tools(ANALYSIS_TOOLS + ("index_repository",))

def test_candidate_environment_is_target_scoped(self):
    env = candidate_environment(self.target, self.cache, base={"PATH": "/usr/bin"})
    self.assertEqual(str(self.target.resolve()), env["CBM_ALLOWED_ROOT"])
    self.assertEqual(str(self.cache.resolve()), env["CBM_CACHE_DIR"])
    self.assertEqual("error", env["CBM_LOG_LEVEL"])

def test_absent_external_candidate_is_cleanly_unavailable(self):
    result = detect_external_candidate(self.root / "missing-binary")
    self.assertEqual("unavailable", result.status)
    self.assertEqual((), result.commands)
```

- [ ] **Step 2: Implement candidate receipts and raw JSON-RPC tool listing**

Start the candidate with `("--tool-profile=analysis",)`, send `initialize`, `notifications/initialized`, and `tools/list` JSON-RPC messages over stdio, then close stdin and enforce the normal timeout cleanup. Sort returned tool names before exact comparison with `ANALYSIS_TOOLS`. `detect_external_candidate` accepts one absolute user-configured path, checks existence and regular-file status, then probes version and tool profile; it never searches `PATH` or executes an installer, updater, or trust mutation.

- [ ] **Step 3: Implement one-shot index commands**

The command constructor must return this argument vector without shell quoting:

```python
(
    str(binary),
    "cli",
    "--progress",
    "index_repository",
    "--repo-path",
    str(target_root.resolve()),
)
```

After indexing, call `list_projects`, select the single entry whose canonical root equals the target, then call `index_status` and `check_index_coverage`. Reject zero projects, multiple matching projects, an out-of-root canonical path, or incomplete status without recording the limitation.

- [ ] **Step 4: Run tests and commit**

```bash
python3 -m unittest tests.kinglet_cbm_eval.test_candidate -v
git add tools/kinglet_cbm_eval/candidate.py tests/kinglet_cbm_eval/test_candidate.py
git commit -m "feat: add pinned candidate readiness checks"
```

---

### Task 6: Construct fixed paired schedules and ephemeral Codex commands

**Files:**
- Create: `tools/kinglet_cbm_eval/runner.py`
- Test: `tests/kinglet_cbm_eval/test_runner.py`

**Interfaces:**
- Pilot schedule: three preregistered tasks, one repetition, two arms, exactly six runs.
- Full schedule: eight tasks, two repetitions, two arms, exactly 32 runs.
- Randomization seed: integer `20260724`.
- Baseline and treatment prompts are byte-identical.
- Treatment adds only the candidate MCP override.

- [ ] **Step 1: Add failing schedule and command-difference tests**

```python
def test_full_schedule_has_fixed_balanced_shape(self):
    schedule = build_schedule(self.tasks, phase="full", seed=20260724)
    self.assertEqual(32, len(schedule))
    self.assertEqual(16, sum(item.arm == "baseline" for item in schedule))
    self.assertEqual(16, sum(item.arm == "treatment" for item in schedule))
    self.assertEqual(schedule, build_schedule(self.tasks, phase="full", seed=20260724))

def test_treatment_diff_is_only_ephemeral_mcp_overrides(self):
    baseline = build_codex_command(self.run, self.policy, arm="baseline")
    treatment = build_codex_command(self.run, self.policy, arm="treatment")
    self.assertEqual(strip_mcp_overrides(baseline), strip_mcp_overrides(treatment))
    self.assertIn('mcp_servers.codebase-memory-mcp.args=["--tool-profile=analysis"]', treatment)
```

- [ ] **Step 2: Implement the exact common Codex command**

```python
common = [
    "codex", "exec",
    "--ephemeral",
    "--json",
    "--color", "never",
    "--sandbox", "read-only",
    "--cd", str(target_root),
    "--output-schema", str(answer_schema),
    "--output-last-message", str(answer_path),
    "--model", model,
    "--config", f'model_reasoning_effort="{reasoning_effort}"',
]
```

Append the exact same prompt string as the final argument in both arms. The prompt is:

```text
You are answering a preregistered repository-understanding task. Do not edit files.
Answer only from the target snapshot. State bounded uncertainty instead of guessing.
Every finding must cite an exact repository-relative path and symbol. For negative or
exhaustive claims, verify source coverage and mention any fallback used.

Task ID: {task_id}
Question: {task_prompt}
```

- [ ] **Step 3: Add treatment-only MCP overrides**

Pass each override as its own `--config` value:

```text
mcp_servers.codebase-memory-mcp.command="<absolute-binary>"
mcp_servers.codebase-memory-mcp.args=["--tool-profile=analysis"]
mcp_servers.codebase-memory-mcp.env={CBM_ALLOWED_ROOT="<absolute-target>",CBM_CACHE_DIR="<absolute-cache>",CBM_LOG_LEVEL="error"}
mcp_servers.codebase-memory-mcp.startup_timeout_sec=10
mcp_servers.codebase-memory-mcp.tool_timeout_sec=30
```

Do not use `--ignore-user-config`; it would remove Superpowers from both the intended workflow and the experiment. Phase 0 must prove these inline overrides start the pinned server without persisting configuration.

- [ ] **Step 4: Implement immutable receipts**

Each run writes `command.json`, `events.jsonl`, `stderr.log`, `answer.json`, and `receipt.json` beneath:

```text
.kinglet/local/experiments/codebase-memory/<experiment-id>/runs/<run-id>/
```

Before a treatment run, copy the target's verified Phase 1 index directory into
`runs/<run-id>/cache/`, verify its manifest hash, and use that private copy as
`CBM_CACHE_DIR`. Baseline runs do not receive the cache path. Record pre-run and post-run cache
manifest hashes; a mutation is a boundary failure. This gives every treatment repetition the same
preindexed graph without sharing mutable SQLite state between runs.

If the exit code is nonzero, timeout occurs, answer parsing fails, telemetry is absent, target HEAD changes, or a global snapshot changes, set `infrastructure_error` and leave the repetition invalid. Never automatically rerun it.

- [ ] **Step 5: Run tests and commit**

```bash
python3 -m unittest tests.kinglet_cbm_eval.test_runner -v
git add tools/kinglet_cbm_eval/runner.py tests/kinglet_cbm_eval/test_runner.py
git commit -m "feat: schedule paired codex evaluations"
```

---

### Task 7: Render sanitized reports and expose the CLI

**Files:**
- Create: `tools/kinglet_cbm_eval/report.py`
- Create: `tools/kinglet_cbm_eval/cli.py`
- Create: `tools/kinglet_cbm_eval/__main__.py`
- Test: `tests/kinglet_cbm_eval/test_report.py`
- Test: `tests/kinglet_cbm_eval/test_cli.py`

**Interfaces:**
- CLI exit `0`: requested operation completed.
- CLI exit `2`: invalid contract/evidence or failed decision gate.
- CLI exit `64`: usage error.
- CLI exit `74`: I/O or infrastructure error.
- Reports omit prompts, absolute paths, raw stderr, global hashes, and full event streams.

- [ ] **Step 1: Add failing deterministic report and CLI tests**

```python
def test_report_is_byte_stable_and_contains_both_decisions(self):
    first = render_json(sample_report())
    second = render_json(sample_report(reversed_inputs=True))
    self.assertEqual(first, second)
    decoded = json.loads(first)
    self.assertIn("development_decision", decoded)
    self.assertIn("product_decision", decoded)
    self.assertNotIn(str(Path.home()), first)

def test_cli_rejects_live_run_without_readiness(self):
    stderr = io.StringIO()
    code = main(["run", "--phase", "pilot", "--experiment", str(self.root)], stderr=stderr)
    self.assertEqual(2, code)
    self.assertIn("E_READINESS", stderr.getvalue())
```

- [ ] **Step 2: Implement deterministic rendering**

The JSON report includes candidate and target commits, tool surface, environment labels, phase status, per-run validity, per-task correctness/tokens/deltas, secondary timings, boundary assertions, pilot stop reasons, and both decisions. Replace every local root with `$KINGLET_TARGET`, `$UNITY_TARGET`, `$CANDIDATE`, or `$EXPERIMENT` before rendering.

The Markdown report contains these fixed sections:

```text
# Codebase Memory Evaluation
## Decision summary
## Candidate and safety boundary
## Readiness
## Direct tool probe
## Pilot
## Full paired experiment
## Development-tool decision
## Optional-provider decision
## Limitations
## Reproduction
```

- [ ] **Step 3: Implement explicit CLI subcommands**

```text
validate --candidate FILE --tasks FILE
readiness --candidate FILE --experiment DIR
probe --candidate FILE --tasks FILE --experiment DIR
schedule --tasks FILE --phase pilot|full --output FILE
run --candidate FILE --tasks FILE --phase pilot|full --experiment DIR
score --candidate FILE --tasks FILE --experiment DIR
report --candidate FILE --tasks FILE --experiment DIR --output DIR
```

No command infers a candidate revision or target root from a moving branch. `run --phase full` refuses unless the pilot receipt exists and `evaluate_pilot` says continue.

- [ ] **Step 4: Run tests and commit**

```bash
python3 -m unittest tests.kinglet_cbm_eval.test_report tests.kinglet_cbm_eval.test_cli -v
git add tools/kinglet_cbm_eval tests/kinglet_cbm_eval
git commit -m "feat: report codebase memory evaluation"
```

---

### Task 8: Preregister the candidate, eight tasks, and test-runner integration

**Files:**
- Create: `spikes/evaluations/codebase-memory/candidate-v1.json`
- Create: `spikes/evaluations/codebase-memory/tasks-v1.json`
- Create: `tests/test-kinglet-cbm-eval.sh`
- Create: `docs/research/codebase-memory/README.md`
- Verify: `tests/run-tests.sh` discovers the new `test-*.sh` bridge automatically; no code change expected

**Candidate contract:**

```json
{
  "schema": "kinglet.cbm-eval.candidate/v1",
  "id": "codebase-memory-97ce23f",
  "repository": "https://github.com/DeusData/codebase-memory-mcp",
  "commit": "97ce23f9827177fff3858831156e9795c6832b18",
  "source_path": ".research/codebase-memory-mcp-eval",
  "binary_path": ".research/codebase-memory-mcp-eval/build/c/codebase-memory-mcp",
  "tool_profile": "analysis",
  "license_spdx": "MIT",
  "license_path": "LICENSE",
  "bundle_policy": "external-only",
  "kinglet_commit": "a49916b77900e87fcbaf226f332f5923faf7dc28",
  "unity_commit": "bd72241ab91c664176091789c9408d676783abec",
  "model": "gpt-5.6-sol",
  "reasoning_effort": "xhigh",
  "codex_version": "0.145.0",
  "timeout_seconds": 900,
  "random_seed": 20260724
}
```

If `gpt-5.6-sol` is not available at execution time, do not silently substitute another model. Amend the preregistration in a new commit before the first Codex pilot run and record the reason.

- [ ] **Step 1: Add the exact eight task IDs**

```text
kinglet.gate-closure
kinglet.publish-flow
kinglet.report-flow
kinglet.build-flow
unity.command-execution
unity.tool-registration
repository.ci-entrypoints
unity.dispatcher-callers
```

Set `pilot: true` only for `kinglet.gate-closure`, `unity.command-execution`, and `repository.ci-entrypoints`.

- [ ] **Step 2: Encode the exact prompts**

| Task | Exact question |
| --- | --- |
| `kinglet.gate-closure` | `How does gate_is_closed decide 0A, 0R, 0C:<client>, 0U, and 0D? Name the exact helpers and state which evidence families 0D does and does not require.` |
| `kinglet.publish-flow` | `Trace a raw spike record from its local path to committed evidence and artifacts. Name the load, validation, copy, write, and overwrite-prevention boundaries in order.` |
| `kinglet.report-flow` | `Trace report generation from published evidence to JSON and Markdown. Explain how an invalid published record affects coverage and how report replacement remains atomic.` |
| `kinglet.build-flow` | `Trace python3 -m tools.kinglet_build build --all --check from CLI parsing through loading, validation, renderer selection, rendering, writing, and drift exit behavior.` |
| `unity.command-execution` | `Trace a WebSocket execute message from message dispatch to Unity main-thread command processing. Name the exact methods that cross each boundary.` |
| `unity.tool-registration` | `Trace how Unity MCP tools are discovered, filtered to enabled tools, converted into a registration payload, and sent over WebSocket. Explain both discovery mechanisms.` |
| `repository.ci-entrypoints` | `List the exact python3 -m entry points used by Kinglet CI for spike reports and generated-product validation, plus the exact Python unittest command used by the spike shell test.` |
| `unity.dispatcher-callers` | `Within MCPForUnity/Editor/Services/Transport production code, identify every direct caller of TransportCommandDispatcher.ExecuteCommandJsonAsync. Is WebSocket the only caller? Explain how you verified the exhaustive claim and any source fallback.` |

- [ ] **Step 3: Encode source-derived facts**

The contract must use the following exact evidence paths and symbols:

| Task | Required evidence |
| --- | --- |
| `kinglet.gate-closure` | `tools/kinglet_spike/cli.py`: `gate_is_closed`, `_gate_0a_files`, `_all_pass`; 0R uses `runtime.`, 0C uses `client.<id>.`, 0U uses `unity.`, and 0D requires runtime plus Unity but no client gate |
| `kinglet.publish-flow` | `tools/kinglet_spike/publish.py`: `_raw_record_path`, `publish_record`, `_copy_exclusive`, `_write_exclusive`; `tools/kinglet_spike/load.py`: `load_record`; `tools/kinglet_spike/validate.py`: `validate_record` |
| `kinglet.report-flow` | `tools/kinglet_spike/report.py`: `load_published_records`, `evaluate_coverage`, `write_reports`, `_atomic_replace`; invalid records are replaced with status `invalid` before coverage |
| `kinglet.build-flow` | `tools/kinglet_build/cli.py`: `main`, `_load_validated`, `_build`; `tools/kinglet_build/loader.py`: `load_graph`, `load_adapter_profiles`; `tools/kinglet_build/validator.py`: `validate_graph`; `tools/kinglet_build/renderers/__init__.py`: `renderer_registry`; `tools/kinglet_build/writer.py`: `write_product` |
| `unity.command-execution` | `MCPForUnity/Editor/Services/Transport/Transports/WebSocketTransportClient.cs`: `HandleMessageAsync`, `HandleExecuteAsync`; `MCPForUnity/Editor/Services/Transport/TransportCommandDispatcher.cs`: `ExecuteCommandJsonAsync`, `RequestMainThreadPump`, `ProcessQueue`, `EnsureInitialised`; `MCPForUnity/Editor/Tools/CommandRegistry.cs`: `Initialize` |
| `unity.tool-registration` | `MCPForUnity/Editor/Services/ToolDiscoveryService.cs`: `DiscoverAllTools`, `GetEnabledTools`; `MCPForUnity/Editor/Services/Transport/Transports/WebSocketTransportClient.cs`: `GetEnabledToolsOnMainThreadAsync`, `SendRegisterToolsAsync`, `SendJsonAsync`; require both `TypeCache` and `AppDomain` discovery |
| `repository.ci-entrypoints` | `.github/workflows/ci.yml`: `python3 -m tools.kinglet_spike report`, `python3 -m tools.kinglet_build validate`, `python3 -m tools.kinglet_build build --all --check`; `tests/test-kinglet-spike.sh`: `python3 -m unittest discover -s tests/kinglet_spike -t . -v` |
| `unity.dispatcher-callers` | `MCPForUnity/Editor/Services/Transport/Transports/WebSocketTransportClient.cs`: `HandleExecuteAsync`; `MCPForUnity/Editor/Services/Transport/Transports/StdioBridgeHost.cs`: `ExecuteQueuedCommand`; both directly call `MCPForUnity/Editor/Services/Transport/TransportCommandDispatcher.cs`: `ExecuteCommandJsonAsync` |

For `unity.dispatcher-callers`, forbid any claim matching `WebSocket (is|as) the only`, `only caller.*WebSocket`, or `no stdio caller`. Require the answer to mention source fallback or full-scope verification whenever `check_index_coverage` is incomplete.

- [ ] **Step 4: Add the shell bridge**

```bash
#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
python3 -m unittest discover -s tests/kinglet_cbm_eval -t . -v
python3 -m tools.kinglet_cbm_eval validate \
  --candidate spikes/evaluations/codebase-memory/candidate-v1.json \
  --tasks spikes/evaluations/codebase-memory/tasks-v1.json
```

Make it executable. The existing `tests/run-tests.sh` glob discovers it automatically; do not add a second explicit invocation.

- [ ] **Step 5: Document reproduction and non-claims**

The README must state that the upstream 99%/120x claim is unverified for Kinglet, this benchmark cannot prove universal savings, the product never bundles the binary, and Windows/macOS/live Unity remain open.

- [ ] **Step 6: Run all harness tests and commit**

```bash
bash tests/test-kinglet-cbm-eval.sh
bash tests/run-tests.sh
git add spikes/evaluations/codebase-memory tests/kinglet_cbm_eval tests/test-kinglet-cbm-eval.sh docs/research/codebase-memory/README.md
git commit -m "test: preregister codebase memory evaluation"
```

---

### Task 9: Execute Phase 0 readiness and safety

**Files:**
- Create ignored: `.research/codebase-memory-mcp-eval/`
- Create ignored: `.research/kinglet-cbm-target/`
- Create ignored: `.kinglet/local/experiments/codebase-memory/20260724-balanced-v1/`
- Update after sanitization: `docs/research/codebase-memory/report.json`
- Update after sanitization: `docs/research/codebase-memory/report.md`

- [ ] **Step 1: Confirm clean source clones and exact identities**

Run:

```bash
git status --short
git -C .research/codebase-memory-mcp status --short
git -C .research/codebase-memory-mcp rev-parse HEAD
git -C .research/unity-mcp status --short
git -C .research/unity-mcp rev-parse HEAD
```

Expected: both research clones are clean; commits equal the candidate contract. Stop on a mismatch.

- [ ] **Step 2: Create detached ignored target worktrees**

```bash
git -C .research/codebase-memory-mcp worktree add --detach ../codebase-memory-mcp-eval 97ce23f9827177fff3858831156e9795c6832b18
git worktree add --detach .research/kinglet-cbm-target a49916b77900e87fcbaf226f332f5923faf7dc28
```

Verify both with `git rev-parse HEAD` and `git status --short`. Do not reuse the mutable main checkout as a benchmark target.

- [ ] **Step 3: Snapshot global state, inspect scripts, run upstream tests, and build**

Run the harness readiness pre-snapshot first. Then execute from `.research/codebase-memory-mcp-eval`:

```bash
bash scripts/test.sh
bash scripts/build.sh --version eval-97ce23f
build/c/codebase-memory-mcp --version
sha256sum build/c/codebase-memory-mcp
cc --version
```

Record exit codes, durations, compiler first line, version output, and binary SHA-256. A failed upstream test is a readiness failure; do not patch upstream inside this experiment.

Do not execute `scripts/smoke-test.sh` or `scripts/smoke-invariants.sh`: the pinned versions invoke
`install`, `update`, `uninstall`, and an installer E2E phase, which violate this evaluation's
approved boundary even when some calls use an isolated HOME or dry-run flag. Record this deliberate
omission as a limitation. The next step replaces only the relevant binary, CLI, MCP lifecycle,
tool-profile, indexing, root-refusal, and cleanup smoke coverage without exercising installer
surfaces.

- [ ] **Step 4: Verify analysis tools, root refusal, and cleanup**

Run:

```bash
python3 -m tools.kinglet_cbm_eval readiness \
  --candidate spikes/evaluations/codebase-memory/candidate-v1.json \
  --experiment .kinglet/local/experiments/codebase-memory/20260724-balanced-v1
```

Expected:

- version, CLI index, MCP initialize/list, malformed-input, and clean-EOF smoke probes pass;
- exact eleven-tool analysis surface;
- no `index_repository`, `delete_project`, `manage_adr`, or `ingest_traces` MCP tool;
- indexing `.research/unity-mcp` with `CBM_ALLOWED_ROOT` set to `.research/kinglet-cbm-target` is refused;
- cache files appear only below the experiment directory;
- no candidate process group remains;
- global snapshots are unchanged.

- [ ] **Step 5: Verify real Codex event shape and treatment override**

Run one non-benchmark preflight in each arm with the answer schema and the same prompt. Require:

- one terminal usage object with all three exact token fields;
- structured answer acceptance;
- treatment MCP startup;
- no persistent Codex configuration change;
- the installed Codex version and preregistered model match the contract;
- Superpowers remains discoverable in both arms.

If any item fails, render an `inconclusive` readiness report and stop. Do not substitute estimated token counts or `--ignore-user-config`.

- [ ] **Step 6: Sanitize, render, review, and commit readiness evidence**

```bash
python3 -m tools.kinglet_cbm_eval report \
  --candidate spikes/evaluations/codebase-memory/candidate-v1.json \
  --tasks spikes/evaluations/codebase-memory/tasks-v1.json \
  --experiment .kinglet/local/experiments/codebase-memory/20260724-balanced-v1 \
  --output docs/research/codebase-memory
git diff --check
git diff -- docs/research/codebase-memory
git add docs/research/codebase-memory
git commit -m "docs: record codebase memory readiness"
```

---

### Task 10: Execute Phase 1 deterministic indexing and tool probes

**Files:**
- Update ignored: `.kinglet/local/experiments/codebase-memory/20260724-balanced-v1/`
- Update: `docs/research/codebase-memory/report.json`
- Update: `docs/research/codebase-memory/report.md`

- [ ] **Step 1: Build fresh isolated indexes**

Use separate cache roots:

```text
indexes/kinglet-cold/
indexes/unity-cold/
indexes/kinglet-refresh-copy/
indexes/unity-refresh-copy/
```

For each target, set `CBM_ALLOWED_ROOT` to that target alone, record cold duration and peak RSS, then run `list_projects`, `index_status`, and `check_index_coverage`. Copy the completed cold cache byte-for-byte to the corresponding `refresh-copy`, record its manifest hash, rerun `index_repository` against the unchanged target using that copied cache, and record the refresh duration. The cache used by Codex treatment runs is copied only from the post-refresh verified cache.

- [ ] **Step 2: Run preregistered direct queries**

Use `search_graph --name-pattern` for every required symbol, `trace_path --direction both` for the execution-flow symbols, `query_graph` only for bounded caller relationships, and `search_code` for literal/config facts. For every path used in a negative or exhaustive conclusion, run `check_index_coverage`; if incomplete, record `source_fallback_required`.

Direct query results are capability evidence only. They do not count as Codex correctness or token evidence.

- [ ] **Step 3: Probe freshness and absence behavior**

In disposable copies beneath the experiment directory:

1. add a uniquely named function;
2. run `detect_changes`;
3. refresh the index explicitly;
4. confirm the new symbol appears;
5. remove the copy;
6. point the treatment at an absent cache and confirm clean filesystem fallback;
7. corrupt a copied cache and confirm clean failure plus fallback;
8. use a partial index and confirm `check_index_coverage` prevents an exhaustive graph-only answer.

No probe may alter the pinned target worktrees.

- [ ] **Step 4: Render and commit the sanitized probe report**

```bash
python3 -m tools.kinglet_cbm_eval probe \
  --candidate spikes/evaluations/codebase-memory/candidate-v1.json \
  --tasks spikes/evaluations/codebase-memory/tasks-v1.json \
  --experiment .kinglet/local/experiments/codebase-memory/20260724-balanced-v1
python3 -m tools.kinglet_cbm_eval report \
  --candidate spikes/evaluations/codebase-memory/candidate-v1.json \
  --tasks spikes/evaluations/codebase-memory/tasks-v1.json \
  --experiment .kinglet/local/experiments/codebase-memory/20260724-balanced-v1 \
  --output docs/research/codebase-memory
git diff --check
git add docs/research/codebase-memory
git commit -m "docs: record codebase memory tool probes"
```

---

### Task 11: Execute the six-run pilot and honor the stop gate

**Files:**
- Update ignored: `.kinglet/local/experiments/codebase-memory/20260724-balanced-v1/`
- Update: `docs/research/codebase-memory/report.json`
- Update: `docs/research/codebase-memory/report.md`

- [ ] **Step 1: Materialize and review the fixed pilot schedule**

```bash
python3 -m tools.kinglet_cbm_eval schedule \
  --tasks spikes/evaluations/codebase-memory/tasks-v1.json \
  --phase pilot \
  --output .kinglet/local/experiments/codebase-memory/20260724-balanced-v1/pilot-schedule.json
```

Expected: exactly six entries covering the three pilot task IDs once per arm. Review target commits, command differences, model, reasoning effort, and cache roots before execution.

- [ ] **Step 2: Run the pilot**

```bash
python3 -m tools.kinglet_cbm_eval run \
  --candidate spikes/evaluations/codebase-memory/candidate-v1.json \
  --tasks spikes/evaluations/codebase-memory/tasks-v1.json \
  --phase pilot \
  --experiment .kinglet/local/experiments/codebase-memory/20260724-balanced-v1
```

Do not rerun an invalid entry under the same run ID. A corrected infrastructure issue requires a new experiment ID and an explicit report note.

- [ ] **Step 3: Score and apply the stop gate**

```bash
python3 -m tools.kinglet_cbm_eval score \
  --candidate spikes/evaluations/codebase-memory/candidate-v1.json \
  --tasks spikes/evaluations/codebase-memory/tasks-v1.json \
  --experiment .kinglet/local/experiments/codebase-memory/20260724-balanced-v1
```

Stop before Phase 3 on lower treatment correctness, a critical false claim, stale graph, incomplete telemetry, boundary write, orphan process, or treatment using more tokens on all three tasks.

- [ ] **Step 4: Publish the pilot result**

Render the report, inspect every scored finding against the raw answer locally, verify no absolute path or prompt leaked, then commit:

```bash
git add docs/research/codebase-memory
git commit -m "docs: record codebase memory pilot"
```

If the pilot stops, set the appropriate decision to `reject` or `inconclusive`, explain the exact stop reason, skip Task 12, and proceed to Tasks 13 and 14.

---

### Task 12: Execute the conditional 32-run full experiment

**Files:**
- Update ignored: `.kinglet/local/experiments/codebase-memory/20260724-balanced-v1/`
- Update: `docs/research/codebase-memory/report.json`
- Update: `docs/research/codebase-memory/report.md`

- [ ] **Step 1: Require a passing pilot and materialize the full schedule**

```bash
python3 -m tools.kinglet_cbm_eval schedule \
  --tasks spikes/evaluations/codebase-memory/tasks-v1.json \
  --phase full \
  --output .kinglet/local/experiments/codebase-memory/20260724-balanced-v1/full-schedule.json
```

Expected: exactly 32 entries, two repetitions per task per arm, fixed by seed `20260724`.

- [ ] **Step 2: Run the full experiment without adaptive prompt changes**

```bash
python3 -m tools.kinglet_cbm_eval run \
  --candidate spikes/evaluations/codebase-memory/candidate-v1.json \
  --tasks spikes/evaluations/codebase-memory/tasks-v1.json \
  --phase full \
  --experiment .kinglet/local/experiments/codebase-memory/20260724-balanced-v1
```

Do not change prompts, fact rules, forbidden claims, model, reasoning effort, timeouts, or target snapshots after seeing any result.

- [ ] **Step 3: Score both arms**

Require all 32 valid receipts. Report individual repetitions, per-task medians, all eight paired reductions, median reduction, range, correctness delta, neutral-or-better count, critical failures, tool calls, duration, and cached input tokens.

- [ ] **Step 4: Review surprising cases against source**

Human review may mark a scorer defect only when the preregistered regex or evidence matcher is mechanically wrong. Fixing the scorer requires:

1. a failing unit test;
2. a code commit describing the defect;
3. rescoring both arms identically;
4. a report note preserving the original and corrected scorer versions.

Human preference cannot override a correctly applied preregistered rule.

- [ ] **Step 5: Render and commit**

```bash
python3 -m tools.kinglet_cbm_eval score \
  --candidate spikes/evaluations/codebase-memory/candidate-v1.json \
  --tasks spikes/evaluations/codebase-memory/tasks-v1.json \
  --experiment .kinglet/local/experiments/codebase-memory/20260724-balanced-v1
python3 -m tools.kinglet_cbm_eval report \
  --candidate spikes/evaluations/codebase-memory/candidate-v1.json \
  --tasks spikes/evaluations/codebase-memory/tasks-v1.json \
  --experiment .kinglet/local/experiments/codebase-memory/20260724-balanced-v1 \
  --output docs/research/codebase-memory
git add docs/research/codebase-memory
git commit -m "docs: record codebase memory full evaluation"
```

---

### Task 13: Record independent development and product decisions

**Files:**
- Update: `docs/research/codebase-memory/report.json`
- Update: `docs/research/codebase-memory/report.md`
- Modify only if approved by the result: a future separate design for optional provider integration

- [ ] **Step 1: Apply the development gate mechanically**

Allowed outcomes:

- `development-only`: all six development criteria pass;
- `reject`: valid evidence fails one or more criteria;
- `inconclusive`: required evidence is unavailable or invalid.

If `development-only`, document the maintainer workflow as external local tooling alongside Superpowers. Do not add the binary, installer, hooks, agent profiles, or global configuration to Kinglet.

- [ ] **Step 2: Apply the product gate independently**

Allowed outcomes:

- `optional-provider-candidate`: development gate passes and all Unity plus fallback requirements pass;
- `reject`;
- `inconclusive`.

`optional-provider-candidate` authorizes only a new brainstorming/design cycle for provider-neutral detection and fallback contracts. It does not authorize implementation or bundling.

- [ ] **Step 3: Record bounded principles separately**

Regardless of provider outcome, list any independently useful principles with evidence:

- freshness must be checked before structural conclusions;
- graph evidence is provisional when coverage is incomplete;
- negative and exhaustive claims require source fallback;
- provider failure must degrade to ordinary source inspection;
- external provider detection must not install, update, or trust it.

Do not copy upstream code or claim these principles as product features before a separate design.

- [ ] **Step 4: Commit the decision report**

```bash
git diff --check
git diff -- docs/research/codebase-memory
git add docs/research/codebase-memory
git commit -m "docs: decide codebase memory adoption scope"
```

---

### Task 14: Final verification and handoff

**Files:**
- Verify all files changed by Tasks 1-13

- [ ] **Step 1: Run focused and aggregate tests**

```bash
bash tests/test-kinglet-cbm-eval.sh
bash tests/run-tests.sh
python3 -m tools.kinglet_build validate
python3 -m tools.kinglet_build build --all --check
python3 -m tools.kinglet_spike report
```

Expected: every command exits `0`; existing generated products are unchanged.

- [ ] **Step 2: Revalidate contracts and deterministic reports**

```bash
python3 -m tools.kinglet_cbm_eval validate \
  --candidate spikes/evaluations/codebase-memory/candidate-v1.json \
  --tasks spikes/evaluations/codebase-memory/tasks-v1.json
python3 -m tools.kinglet_cbm_eval report \
  --candidate spikes/evaluations/codebase-memory/candidate-v1.json \
  --tasks spikes/evaluations/codebase-memory/tasks-v1.json \
  --experiment .kinglet/local/experiments/codebase-memory/20260724-balanced-v1 \
  --output docs/research/codebase-memory
git diff --exit-code -- docs/research/codebase-memory/report.json docs/research/codebase-memory/report.md
```

Expected: contract validation passes and regeneration is byte-stable.

- [ ] **Step 3: Scan for placeholders, leaked local data, and forbidden integration**

```bash
rg -n 'TODO|TBD|PLACEHOLDER' \
  tools/kinglet_cbm_eval spikes/evaluations/codebase-memory docs/research/codebase-memory
rg -n '/home/|/Users/|[A-Za-z]:\\\\' \
  docs/research/codebase-memory/report.json docs/research/codebase-memory/report.md
git ls-files .research .kinglet/local
rg -n 'install|update|uninstall|--with-ui|tool-profile=all' \
  spikes/evaluations/codebase-memory docs/research/codebase-memory
git status --short
git diff --check
```

Expected: the placeholder, absolute-path, and tracked-local-data scans have no matches. Any final integration-term match exists only in explicit prohibition or historical explanation, never an executable command. No `.research/`, `.kinglet/local/`, binary, cache, raw event, or absolute path is tracked.

- [ ] **Step 4: Inspect commit sequence and final diff**

```bash
git log --oneline --decorate -20
git diff origin/main...HEAD --stat
git status --short --branch
```

Expected: implementation, preregistration, readiness, probe, pilot, optional full run, and decision evidence are reviewable as distinct commits; the worktree is clean.

- [ ] **Step 5: Request code and evidence review**

Use `superpowers:requesting-code-review` to verify:

- the implementation follows this plan and the approved design;
- no acceptance threshold was changed after results;
- exact token telemetry, target commits, candidate hash, and global-state assertions are present;
- both decisions follow their independent gates;
- the report does not imply Windows, macOS, or live-Unity validation.

Fix any verified issue with a failing test or report assertion, rerun Steps 1-4, and commit the correction before handoff.
