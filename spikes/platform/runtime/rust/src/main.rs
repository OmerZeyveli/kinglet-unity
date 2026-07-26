//! Rust host probe candidate for the kinglet "0R runtime bake-off" spike.
//!
//! Frozen executable protocol (identical to the Go and Python candidates):
//!
//! ```text
//! <exe> --version
//!     → prints "rust 1.97.1"
//! <exe> run --contract <abs host-probe-v1.json> --workspace <abs dir> --result <abs result.json>
//!     → exits 0 iff all 18 assertions pass; atomically writes a
//!       kinglet.host-probe.result/v1 JSON document to --result.
//! <exe> child --sentinel <abs file> --lifetime-ms <positive int>
//!     → spawns exactly one grandchild, writes [child_pid, grandchild_pid] to
//!       the sentinel, then sleeps.
//! ```

mod lease;
mod process;

use std::fs;
use std::path::{Path, PathBuf};
use std::process::exit;
use std::thread::sleep;
use std::time::{Duration, Instant};

use ed25519_dalek::{Signature, VerifyingKey};
use serde::Deserialize;
use serde_json::json;
use sha2::{Digest, Sha256};

use lease::{atomic_replace, Lease};

const CANDIDATE_ID: &str = "rust";
const CANDIDATE_VERSION: &str = "1.97.1";
const RESULT_SCHEMA: &str = "kinglet.host-probe.result/v1";

/// The 18 required assertion ids, in frozen order.
const REQUIRED_ASSERTIONS: [&str; 18] = [
    "manifest.accept-valid",
    "manifest.reject-unknown",
    "path.unicode-space",
    "filesystem.atomic-replace",
    "lease.acquire",
    "lease.renew",
    "lease.reject-competitor",
    "lease.expire",
    "lease.release",
    "process.child-grandchild",
    "process.cancel",
    "process.no-descendants",
    "crypto.sha256",
    "crypto.ed25519",
    "cleanup.success",
    "cleanup.crash",
    "cleanup.timeout",
    "cleanup.cancel",
];

// ---------------------------------------------------------------------------
// Contract / fixture structs
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize, Default)]
struct TimingsMs {
    #[serde(default)]
    lease_ttl: u64,
    #[serde(default)]
    lease_renewal: u64,
    #[serde(default)]
    lease_competitor_attempt: u64,
    #[serde(default)]
    child_lifetime: u64,
    #[serde(default)]
    cancel_deadline: u64,
}

#[derive(Debug, Deserialize)]
struct Contract {
    #[serde(default)]
    timings_ms: TimingsMs,
    #[serde(default)]
    canonical_valid: Option<String>,
    #[serde(default)]
    canonical_invalid: Option<String>,
    #[serde(default)]
    crypto_vectors: Option<String>,
}

#[derive(Debug, Deserialize)]
struct Ed25519Vector {
    message: String,
    public_key: String,
    signature: String,
}

// --- role.json manifest, strictly decoded ---

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RoleSupportEntry {
    #[allow(dead_code)]
    state: String,
    #[serde(default)]
    #[allow(dead_code)]
    reason: Option<String>,
    #[serde(default)]
    #[allow(dead_code)]
    owner: Option<String>,
    #[serde(default)]
    #[allow(dead_code)]
    test: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RoleProvenance {
    #[allow(dead_code)]
    origin: String,
    #[allow(dead_code)]
    upstream_version: String,
    #[allow(dead_code)]
    upstream_path: String,
    #[allow(dead_code)]
    upstream_sha256: String,
}

/// Canonical role.json manifest. `deny_unknown_fields` is the whole point:
/// the canonical-invalid fixture injects a top-level `"unknown": true`, which
/// must fail decoding and thereby satisfy `manifest.reject-unknown`.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RoleManifest {
    #[allow(dead_code)]
    schema_version: i64,
    id: String,
    #[allow(dead_code)]
    kind: String,
    #[allow(dead_code)]
    name: String,
    #[allow(dead_code)]
    summary: String,
    #[allow(dead_code)]
    capabilities: Vec<String>,
    #[allow(dead_code)]
    requires: Vec<String>,
    #[allow(dead_code)]
    support: std::collections::BTreeMap<String, RoleSupportEntry>,
    #[allow(dead_code)]
    provenance: RoleProvenance,
    #[allow(dead_code)]
    reasoning_tier: String,
    #[allow(dead_code)]
    evidence: Vec<String>,
}

/// Strictly decode a role.json. Returns Ok(()) only if it parses under
/// `deny_unknown_fields` and carries a non-empty id.
fn decode_role_manifest(path: &Path) -> Result<(), String> {
    let bytes = fs::read(path).map_err(|e| format!("read {}: {}", path.display(), e))?;
    let role: RoleManifest =
        serde_json::from_slice(&bytes).map_err(|e| format!("decode: {}", e))?;
    if role.id.is_empty() {
        return Err("role.json missing id".to_string());
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Ed25519 verification (brief's exact snippet)
// ---------------------------------------------------------------------------

fn verify_ed25519(vector: &Ed25519Vector) -> Result<(), String> {
    // Empty message hex => empty byte slice.
    let message = if vector.message.is_empty() {
        Vec::new()
    } else {
        hex::decode(&vector.message).map_err(|e| format!("decode message: {}", e))?
    };
    let public_key =
        hex::decode(&vector.public_key).map_err(|e| format!("decode public key: {}", e))?;
    let signature_bytes =
        hex::decode(&vector.signature).map_err(|e| format!("decode signature: {}", e))?;

    let key = VerifyingKey::from_bytes(
        &public_key
            .as_slice()
            .try_into()
            .map_err(|_| "public key length != 32".to_string())?,
    )
    .map_err(|e| format!("from_bytes: {}", e))?;
    let signature =
        Signature::from_slice(&signature_bytes).map_err(|e| format!("from_slice: {}", e))?;
    key.verify_strict(&message, &signature)
        .map_err(|e| format!("verify_strict: {}", e))?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Assertion accumulation
// ---------------------------------------------------------------------------

struct AssertionResult {
    status: String,
    reason: Option<String>,
}

struct Recorder {
    results: std::collections::BTreeMap<String, AssertionResult>,
    errors: Vec<String>,
}

impl Recorder {
    fn new() -> Self {
        Recorder {
            results: std::collections::BTreeMap::new(),
            errors: Vec::new(),
        }
    }

    fn pass(&mut self, id: &str) {
        self.results.entry(id.to_string()).or_insert(AssertionResult {
            status: "pass".to_string(),
            reason: None,
        });
    }

    fn fail(&mut self, id: &str, reason: impl Into<String>) {
        let reason = reason.into();
        self.errors.push(format!("{}: {}", id, reason));
        self.results.entry(id.to_string()).or_insert(AssertionResult {
            status: "fail".to_string(),
            reason: Some(reason),
        });
    }

    fn record(&mut self, id: &str, ok: Result<(), String>) {
        match ok {
            Ok(()) => self.pass(id),
            Err(e) => self.fail(id, e),
        }
    }
}

// ---------------------------------------------------------------------------
// The `run` subcommand: execute all 18 assertions
// ---------------------------------------------------------------------------

fn run_contract(contract_path: &Path, workspace: &Path) -> Result<serde_json::Value, String> {
    let contract_path = fs::canonicalize(contract_path)
        .map_err(|e| format!("canonicalize contract: {}", e))?;
    fs::create_dir_all(workspace).map_err(|e| format!("mkdir workspace: {}", e))?;
    let workspace = fs::canonicalize(workspace)
        .map_err(|e| format!("canonicalize workspace: {}", e))?;

    let contract_dir = contract_path
        .parent()
        .ok_or_else(|| "contract has no parent directory".to_string())?
        .to_path_buf();

    let raw = fs::read(&contract_path).map_err(|e| format!("read contract: {}", e))?;
    let contract: Contract =
        serde_json::from_slice(&raw).map_err(|e| format!("parse contract: {}", e))?;

    let lease_ttl = nonzero(contract.timings_ms.lease_ttl, 1200);
    let lease_renewal = nonzero(contract.timings_ms.lease_renewal, 400);
    let lease_competitor = nonzero(contract.timings_ms.lease_competitor_attempt, 600);
    let child_lifetime = nonzero(contract.timings_ms.child_lifetime, 30000);
    let cancel_deadline = nonzero(contract.timings_ms.cancel_deadline, 5000);

    let canonical_valid = contract
        .canonical_valid
        .as_deref()
        .unwrap_or("canonical-valid/");
    let canonical_invalid = contract
        .canonical_invalid
        .as_deref()
        .unwrap_or("canonical-invalid/");
    let crypto_vectors = contract
        .crypto_vectors
        .as_deref()
        .unwrap_or("ed25519-rfc8032.json");

    let mut rec = Recorder::new();
    let mut descendant_pids: Vec<i64> = Vec::new();

    // -- 1. manifest.accept-valid --
    {
        let role = contract_dir
            .join(canonical_valid.trim_end_matches('/'))
            .join("src/roles/unity-scout/role.json");
        rec.record("manifest.accept-valid", decode_role_manifest(&role));
    }

    // -- 2. manifest.reject-unknown --
    {
        let role = contract_dir
            .join(canonical_invalid.trim_end_matches('/'))
            .join("src/roles/unity-scout/role.json");
        match decode_role_manifest(&role) {
            Err(_) => rec.pass("manifest.reject-unknown"), // rejection is success
            Ok(()) => rec.fail(
                "manifest.reject-unknown",
                "decoder accepted a manifest with an unknown field",
            ),
        }
    }

    // -- 3. path.unicode-space --
    {
        let unicode_file = workspace.join("ünïcödé spàce.txt");
        let outcome = (|| -> Result<(), String> {
            fs::write(&unicode_file, b"ok").map_err(|e| format!("write: {}", e))?;
            let content = fs::read(&unicode_file).map_err(|e| format!("read: {}", e))?;
            if content != b"ok" {
                return Err("unexpected content".to_string());
            }
            Ok(())
        })();
        rec.record("path.unicode-space", outcome);
    }

    // -- 4. filesystem.atomic-replace --
    {
        let target = workspace.join("atomic-state.json");
        let outcome = (|| -> Result<(), String> {
            atomic_replace(&target, b"{\"initial\": true}\n")
                .map_err(|e| format!("first replace: {}", e))?;
            atomic_replace(&target, b"{\"replaced\": true}\n")
                .map_err(|e| format!("second replace: {}", e))?;
            let data = fs::read(&target).map_err(|e| format!("read back: {}", e))?;
            let value: serde_json::Value =
                serde_json::from_slice(&data).map_err(|e| format!("parse: {}", e))?;
            if value.get("replaced") != Some(&serde_json::Value::Bool(true)) {
                return Err("second write did not win".to_string());
            }
            // No leftover temp files in the workspace.
            for entry in fs::read_dir(&workspace).map_err(|e| format!("readdir: {}", e))? {
                let entry = entry.map_err(|e| format!("dirent: {}", e))?;
                if entry.file_name().to_string_lossy().ends_with(".tmp") {
                    return Err(format!(
                        "leftover temp file: {}",
                        entry.file_name().to_string_lossy()
                    ));
                }
            }
            Ok(())
        })();
        rec.record("filesystem.atomic-replace", outcome);
    }

    // -- 5-9. lease lifecycle --
    let lease_path = workspace.join(".lease").join("kinglet.lease");
    let mut lease_a = Lease::new(&lease_path, lease_ttl);

    // lease.acquire
    match lease_a.acquire() {
        Ok(true) if lease_a.owner().is_some() => rec.pass("lease.acquire"),
        Ok(_) => rec.fail("lease.acquire", "acquire returned false"),
        Err(e) => rec.fail("lease.acquire", e.to_string()),
    }

    // lease.renew
    sleep(Duration::from_millis(lease_renewal));
    match lease_a.renew() {
        Ok(true) => rec.pass("lease.renew"),
        Ok(false) => rec.fail("lease.renew", "renew returned false"),
        Err(e) => rec.fail("lease.renew", e.to_string()),
    }

    // lease.reject-competitor — while lease_a is still live
    {
        let extra = lease_competitor.saturating_sub(lease_renewal);
        if extra > 0 {
            sleep(Duration::from_millis(extra));
        }
        let mut competitor = Lease::new(&lease_path, lease_ttl);
        match competitor.acquire() {
            Ok(false) => rec.pass("lease.reject-competitor"),
            Ok(true) => {
                let _ = competitor.release();
                rec.fail("lease.reject-competitor", "competitor acquired a live lease");
            }
            Err(e) => rec.fail("lease.reject-competitor", e.to_string()),
        }
    }

    // lease.expire — short TTL lease, wait past it, steal
    {
        let short_path = workspace.join(".lease").join("short.lease");
        let mut short = Lease::new(&short_path, 100);
        let outcome = (|| -> Result<(), String> {
            if !short.acquire().map_err(|e| e.to_string())? {
                return Err("could not acquire short lease".to_string());
            }
            sleep(Duration::from_millis(350)); // outlive the 100ms TTL
            let mut stealer = Lease::new(&short_path, lease_ttl);
            if !stealer.acquire().map_err(|e| e.to_string())? {
                return Err("could not steal expired lease".to_string());
            }
            stealer.release().map_err(|e| e.to_string())?;
            Ok(())
        })();
        rec.record("lease.expire", outcome);
    }

    // lease.release
    match lease_a.release() {
        Ok(true) if !lease_path.exists() => rec.pass("lease.release"),
        Ok(released) => rec.fail(
            "lease.release",
            format!("released={} file_exists={}", released, lease_path.exists()),
        ),
        Err(e) => rec.fail("lease.release", e.to_string()),
    }

    // -- 10-12. process tree --
    {
        let exe = std::env::current_exe().map_err(|e| format!("current_exe: {}", e))?;
        match spawn_tree_and_cancel(&exe, &workspace, child_lifetime, cancel_deadline) {
            Ok((pids, killed)) => {
                if pids.len() >= 2 {
                    rec.pass("process.child-grandchild");
                } else {
                    rec.fail(
                        "process.child-grandchild",
                        format!("sentinel recorded only {} pids", pids.len()),
                    );
                }

                if !pids.is_empty() && killed {
                    rec.pass("process.cancel");
                } else if !killed {
                    rec.fail("process.cancel", "kill_tree syscall failed");
                } else {
                    rec.fail("process.cancel", "no pids recorded");
                }

                let alive: Vec<i64> = pids
                    .iter()
                    .copied()
                    .filter(|&pid| process::is_pid_alive(pid as i32))
                    .collect();
                if alive.is_empty() {
                    rec.pass("process.no-descendants");
                } else {
                    descendant_pids = alive.clone();
                    rec.fail(
                        "process.no-descendants",
                        format!("pids still alive: {:?}", alive),
                    );
                }
            }
            Err(e) => {
                rec.fail("process.child-grandchild", e.clone());
                rec.fail("process.cancel", e.clone());
                rec.fail("process.no-descendants", e);
            }
        }
    }

    // -- 13. crypto.sha256 (empty input) --
    {
        let digest = Sha256::digest(b"");
        let got = hex::encode(digest);
        let expected = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
        if got == expected {
            rec.pass("crypto.sha256");
        } else {
            rec.fail("crypto.sha256", format!("got {}", got));
        }
    }

    // -- 14. crypto.ed25519 (RFC 8032 vector 1) --
    {
        let vectors_path = contract_dir.join(crypto_vectors);
        let outcome = (|| -> Result<(), String> {
            let raw = fs::read(&vectors_path).map_err(|e| format!("read vectors: {}", e))?;
            let vector: Ed25519Vector =
                serde_json::from_slice(&raw).map_err(|e| format!("parse vectors: {}", e))?;
            verify_ed25519(&vector)
        })();
        rec.record("crypto.ed25519", outcome);
    }

    // -- 15-18. cleanup scenarios: real lease acquire + guaranteed release --
    run_cleanup_scenario(&mut rec, "cleanup.success", &workspace, lease_ttl, Outcome::Success);
    run_cleanup_scenario(&mut rec, "cleanup.crash", &workspace, lease_ttl, Outcome::Crash);
    run_cleanup_scenario(&mut rec, "cleanup.timeout", &workspace, lease_ttl, Outcome::Timeout);
    run_cleanup_scenario(&mut rec, "cleanup.cancel", &workspace, lease_ttl, Outcome::Cancel);

    // -- active lease check: no lease file may survive --
    let lease_paths = [
        lease_path.clone(),
        workspace.join(".cleanup").join("success.lease"),
        workspace.join(".cleanup").join("crash.lease"),
        workspace.join(".cleanup").join("timeout.lease"),
        workspace.join(".cleanup").join("cancel.lease"),
    ];
    let active_lease = lease_paths.iter().any(|p| p.exists());

    // -- assemble ordered result --
    let mut all_pass = true;
    let mut assertions = Vec::with_capacity(REQUIRED_ASSERTIONS.len());
    for id in REQUIRED_ASSERTIONS.iter() {
        let (status, _reason) = match rec.results.get(*id) {
            Some(r) => (r.status.clone(), r.reason.clone()),
            None => {
                rec.errors.push(format!("{}: not reached", id));
                ("fail".to_string(), Some("not reached".to_string()))
            }
        };
        if status != "pass" {
            all_pass = false;
        }
        assertions.push(json!({ "id": id, "status": status }));
    }

    if !descendant_pids.is_empty() || active_lease {
        all_pass = false;
    }

    let status = if all_pass { "pass" } else { "fail" };

    let result = json!({
        "schema": RESULT_SCHEMA,
        "candidate": { "id": CANDIDATE_ID, "version": CANDIDATE_VERSION },
        "status": status,
        "errors": rec.errors,
        "assertions": assertions,
        "descendant_pids": descendant_pids,
        "active_lease": active_lease,
    });

    Ok(result)
}

fn nonzero(value: u64, default: u64) -> u64 {
    if value == 0 { default } else { value }
}

/// Cleanup scenario kinds. Each acquires a lease and guarantees release via a
/// drop guard even when the body panics or bails early.
enum Outcome {
    Success,
    Crash,
    Timeout,
    Cancel,
}

/// A guard that releases a lease and clears a temp file when dropped — so the
/// lease is freed on the normal path, on an early `return`, and on `panic`.
struct CleanupGuard {
    lease: Lease,
    tmp: Option<PathBuf>,
}

impl Drop for CleanupGuard {
    fn drop(&mut self) {
        let _ = self.lease.release();
        if let Some(tmp) = &self.tmp {
            let _ = fs::remove_file(tmp);
        }
    }
}

fn run_cleanup_scenario(
    rec: &mut Recorder,
    id: &str,
    workspace: &Path,
    lease_ttl: u64,
    outcome: Outcome,
) {
    let lease_name = match outcome {
        Outcome::Success => "success.lease",
        Outcome::Crash => "crash.lease",
        Outcome::Timeout => "timeout.lease",
        Outcome::Cancel => "cancel.lease",
    };
    let lease_path = workspace.join(".cleanup").join(lease_name);
    let tmp_path = workspace.join(format!("cleanup-{}.tmp", lease_name));

    // The scenario runs inside a closure; a panic is caught so cleanup.crash can
    // observe that the drop guard released the lease despite unwinding. The
    // default panic hook is silenced for the duration so the deliberate
    // simulated crash does not print a spurious backtrace to stderr.
    let scenario_workspace = workspace.to_path_buf();
    let previous_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(|_| {}));
    let scenario = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut lease = Lease::new(&lease_path, lease_ttl);
        let acquired = lease.acquire().expect("cleanup: acquire lease");
        assert!(acquired, "cleanup: lease should be acquirable");
        let mut guard = CleanupGuard {
            lease,
            tmp: Some(tmp_path.clone()),
        };

        match outcome {
            Outcome::Success => {
                atomic_replace(&tmp_path, b"ok").expect("cleanup: atomic write");
            }
            Outcome::Crash => {
                // Simulate a crash mid-work; the guard must still release.
                let _ = &scenario_workspace;
                panic!("simulated crash");
            }
            Outcome::Timeout => {
                // Simulate a deadline being exceeded, then bail — guard releases.
                guard.tmp = None;
                return;
            }
            Outcome::Cancel => {
                // Simulate a cancellation, then bail — guard releases.
                guard.tmp = None;
                return;
            }
        }
        // guard drops here on the normal path
    }));
    std::panic::set_hook(previous_hook);

    // Regardless of panic/early-return, the lease file must be gone.
    if lease_path.exists() {
        rec.fail(id, "lease not released after cleanup");
        return;
    }
    match (&outcome, scenario) {
        // Crash is expected to unwind; catching it and finding the lease gone is success.
        (Outcome::Crash, Err(_)) => rec.pass(id),
        (Outcome::Crash, Ok(())) => rec.fail(id, "expected simulated crash to unwind"),
        (_, Ok(())) => rec.pass(id),
        (_, Err(_)) => rec.fail(id, "unexpected panic in cleanup scenario"),
    }
}

/// Spawn the child tree, poll for its sentinel, kill the group, and confirm
/// every recorded PID is gone. Returns (recorded_pids, kill_succeeded).
fn spawn_tree_and_cancel(
    exe: &Path,
    workspace: &Path,
    lifetime_ms: u64,
    cancel_deadline_ms: u64,
) -> Result<(Vec<i64>, bool), String> {
    let sentinel = workspace.join("tree-sentinel.json");
    let _ = fs::remove_file(&sentinel);

    let tree = process::spawn_child_tree(exe, &sentinel, lifetime_ms)
        .map_err(|e| format!("spawn child: {}", e))?;

    // Poll for the sentinel (must contain >= 2 pids).
    let deadline = Instant::now() + Duration::from_millis(cancel_deadline_ms);
    let mut pids: Vec<i64> = Vec::new();
    while Instant::now() < deadline {
        if let Ok(data) = fs::read(&sentinel) {
            if let Ok(parsed) = serde_json::from_slice::<Vec<i64>>(&data) {
                if parsed.len() >= 2 {
                    pids = parsed;
                    break;
                }
            }
        }
        sleep(Duration::from_millis(50));
    }

    // Kill the whole group/job; capture whether the syscall succeeded.
    let killed = process::kill_tree(&tree).is_ok();

    // Reap the direct child so it does not linger as a zombie.
    let mut tree = tree;
    let _ = tree.child.wait();

    // Give the OS a moment to reap the grandchild.
    sleep(Duration::from_millis(150));

    // Wait up to 5s for every recorded PID to disappear.
    let liveness_deadline = Instant::now() + Duration::from_secs(5);
    while Instant::now() < liveness_deadline {
        if pids.iter().all(|&pid| !process::is_pid_alive(pid as i32)) {
            break;
        }
        sleep(Duration::from_millis(100));
    }

    Ok((pids, killed))
}

// ---------------------------------------------------------------------------
// The `child` subcommand
// ---------------------------------------------------------------------------

fn run_child(sentinel: &Path, lifetime_ms: u64) -> Result<(), String> {
    if let Some(parent) = sentinel.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("child mkdir: {}", e))?;
    }

    let exe = std::env::current_exe().map_err(|e| format!("current_exe: {}", e))?;
    let gc_sentinel = sentinel
        .parent()
        .unwrap_or_else(|| Path::new("."))
        .join("gc-sentinel.json");

    // Spawn exactly one grandchild that INHERITS our process group, so the
    // harness's group/job kill reaches it too. Long lifetime so it is
    // definitely alive when the harness cancels the tree.
    let grandchild = process::spawn_child_inheriting_group(&exe, &gc_sentinel, 60_000)
        .map_err(|e| format!("child: spawn grandchild: {}", e))?;
    let gc_pid = grandchild.id() as i64;

    // Let the grandchild get going.
    sleep(Duration::from_millis(100));

    let my_pid = std::process::id() as i64;
    let payload = serde_json::to_vec(&vec![my_pid, gc_pid])
        .map_err(|e| format!("child: marshal pids: {}", e))?;
    fs::write(sentinel, &payload).map_err(|e| format!("child: write sentinel: {}", e))?;

    // Sleep out our lifetime; the harness kills the group before this returns.
    sleep(Duration::from_millis(lifetime_ms));

    // Keep the grandchild handle alive until here so it is not dropped early.
    let _ = grandchild;
    Ok(())
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

fn usage() {
    eprintln!(
        "Usage:
  kinglet-host-probe --version
  kinglet-host-probe run --contract <path> --workspace <dir> --result <path>
  kinglet-host-probe child --sentinel <path> --lifetime-ms <ms>"
    );
}

/// Extract the value following `--flag` from `args`.
fn flag_value(args: &[String], flag: &str) -> Option<String> {
    args.iter()
        .position(|a| a == flag)
        .and_then(|i| args.get(i + 1))
        .cloned()
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() {
        usage();
        exit(1);
    }

    match args[0].as_str() {
        "--version" => {
            println!("{} {}", CANDIDATE_ID, CANDIDATE_VERSION);
            exit(0);
        }
        "run" => {
            let contract = flag_value(&args, "--contract");
            let workspace = flag_value(&args, "--workspace");
            let result = flag_value(&args, "--result");
            let (contract, workspace, result) = match (contract, workspace, result) {
                (Some(c), Some(w), Some(r)) => (c, w, r),
                _ => {
                    eprintln!("run: --contract, --workspace, and --result are required");
                    exit(2);
                }
            };

            let value = match run_contract(Path::new(&contract), Path::new(&workspace)) {
                Ok(v) => v,
                Err(e) => {
                    eprintln!("run: {}", e);
                    exit(1);
                }
            };

            let mut serialized = match serde_json::to_vec_pretty(&value) {
                Ok(b) => b,
                Err(e) => {
                    eprintln!("run: serialize result: {}", e);
                    exit(1);
                }
            };
            serialized.push(b'\n');

            if let Err(e) = atomic_replace(Path::new(&result), &serialized) {
                eprintln!("run: write result: {}", e);
                exit(1);
            }

            if value.get("status").and_then(|s| s.as_str()) == Some("pass") {
                exit(0);
            }
            exit(1);
        }
        "child" => {
            let sentinel = flag_value(&args, "--sentinel");
            let lifetime = flag_value(&args, "--lifetime-ms");
            let sentinel = match sentinel {
                Some(s) => s,
                None => {
                    eprintln!("child: --sentinel is required");
                    exit(2);
                }
            };
            let lifetime_ms: u64 = match lifetime.and_then(|v| v.parse().ok()) {
                Some(n) if n > 0 => n,
                _ => {
                    eprintln!("child: --lifetime-ms must be a positive integer");
                    exit(2);
                }
            };
            if let Err(e) = run_child(Path::new(&sentinel), lifetime_ms) {
                eprintln!("child: {}", e);
                exit(1);
            }
            exit(0);
        }
        _ => {
            usage();
            exit(1);
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    /// The frozen RFC 8032 §7.1 test vector 1 (empty message) must verify.
    #[test]
    fn rfc8032_vector_verifies() {
        let vector = Ed25519Vector {
            message: "".to_string(),
            public_key: "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
                .to_string(),
            signature: "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
                .to_string(),
        };
        verify_ed25519(&vector).expect("RFC 8032 vector 1 must verify");
    }

    /// atomic_replace must work when the workspace path contains both a unicode
    /// character and a space, then survive a second replacement.
    #[test]
    fn atomic_replace_survives_unicode_space_path() {
        let dir = std::env::temp_dir()
            .join(format!("kinglet host {}", uuid::Uuid::new_v4()))
            .join("Kral Yalıçapkını");
        fs::create_dir_all(&dir).unwrap();
        let target = dir.join("atomic ünïcödé.json");

        atomic_replace(&target, b"{\"initial\": true}\n").unwrap();
        atomic_replace(&target, b"{\"replaced\": true}\n").unwrap();

        let data = fs::read(&target).unwrap();
        let value: serde_json::Value = serde_json::from_slice(&data).unwrap();
        assert_eq!(value.get("replaced"), Some(&serde_json::Value::Bool(true)));

        // No leftover temp files.
        let leftovers: Vec<_> = fs::read_dir(&dir)
            .unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().ends_with(".tmp"))
            .collect();
        assert!(leftovers.is_empty(), "atomic replace left temp files behind");

        let _ = fs::remove_dir_all(&dir);
    }
}
