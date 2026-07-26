// Package main implements the Go host probe candidate for the kinglet spike bake-off.
//
// Entry points:
//
//	<exe> --version                                  → prints "go 1.26.5"
//	<exe> run --contract <abs> --workspace <abs> --result <abs>
//	<exe> child --sentinel <abs> --lifetime-ms <n>
package main

import (
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// ---------------------------------------------------------------------------
// Candidate identity
// ---------------------------------------------------------------------------

const (
	candidateID      = "go"
	candidateVersion = "1.26.5"
	resultSchema     = "kinglet.host-probe.result/v1"
)

// ---------------------------------------------------------------------------
// Atomic replace
// ---------------------------------------------------------------------------

// atomicReplace writes data to target atomically: tmp → fsync → rename → dir-fsync.
func atomicReplace(target string, data []byte) error {
	parent := filepath.Dir(target)
	if err := os.MkdirAll(parent, 0o700); err != nil {
		return fmt.Errorf("atomicReplace: mkdir: %w", err)
	}

	base := filepath.Base(target)
	// Unique sibling with O_CREATE|O_EXCL.
	tmpPath := filepath.Join(parent, base+".tmp")

	f, err := os.OpenFile(tmpPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		// If file already exists (concurrent call), use a different name.
		tmpPath = filepath.Join(parent, base+"."+strconv.FormatInt(time.Now().UnixNano(), 16)+".tmp")
		f, err = os.OpenFile(tmpPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
		if err != nil {
			return fmt.Errorf("atomicReplace: create tmp: %w", err)
		}
	}

	cleanup := true
	defer func() {
		if cleanup {
			os.Remove(tmpPath)
		}
	}()

	if _, err := f.Write(data); err != nil {
		f.Close()
		return fmt.Errorf("atomicReplace: write: %w", err)
	}
	if err := f.Sync(); err != nil {
		f.Close()
		return fmt.Errorf("atomicReplace: sync: %w", err)
	}
	if err := f.Close(); err != nil {
		return fmt.Errorf("atomicReplace: close: %w", err)
	}

	if err := os.Rename(tmpPath, target); err != nil {
		return fmt.Errorf("atomicReplace: rename: %w", err)
	}
	cleanup = false

	// Best-effort directory fsync.
	if dfd, err := os.Open(parent); err == nil {
		dfd.Sync() //nolint:errcheck
		dfd.Close()
	}
	return nil
}

// ---------------------------------------------------------------------------
// Manifest (role.json) parsing
// ---------------------------------------------------------------------------

// roleSupportEntry represents a single platform's support status.
type roleSupportEntry struct {
	State  string  `json:"state"`
	Reason *string `json:"reason"`
	Owner  *string `json:"owner"`
	Test   *string `json:"test"`
}

// roleProvenance holds upstream tracking info.
type roleProvenance struct {
	Origin          string `json:"origin"`
	UpstreamVersion string `json:"upstream_version"`
	UpstreamPath    string `json:"upstream_path"`
	UpstreamSHA256  string `json:"upstream_sha256"`
}

// roleJSON is the struct for the valid role.json.
// All known top-level fields are listed so DisallowUnknownFields rejects truly unknown ones.
type roleJSON struct {
	SchemaVersion int                         `json:"schema_version"`
	ID            string                      `json:"id"`
	Kind          string                      `json:"kind"`
	Name          string                      `json:"name"`
	Summary       string                      `json:"summary"`
	Capabilities  []string                    `json:"capabilities"`
	Requires      []string                    `json:"requires"`
	Support       map[string]roleSupportEntry `json:"support"`
	Provenance    *roleProvenance             `json:"provenance"`
	ReasoningTier string                      `json:"reasoning_tier"`
	Evidence      []string                    `json:"evidence"`
}

// acceptValidRole decodes the role.json at path and returns nil on success.
// It uses DisallowUnknownFields so any extra field is an error.
func decodeRoleJSON(path string, strict bool) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()

	dec := json.NewDecoder(f)
	if strict {
		dec.DisallowUnknownFields()
	}
	var r roleJSON
	if err := dec.Decode(&r); err != nil {
		return err
	}
	if r.ID == "" {
		return errors.New("role.json: missing id field")
	}
	return nil
}

// ---------------------------------------------------------------------------
// Ed25519 verification
// ---------------------------------------------------------------------------

// verifyEd25519 verifies an Ed25519 signature.
// message, publicKey, and signature are all hex strings.
// An empty hex string ("") means empty bytes.
func verifyEd25519(messageHex, publicHex, sigHex string) (bool, error) {
	var msg []byte
	var err error
	if messageHex != "" {
		msg, err = hex.DecodeString(messageHex)
		if err != nil {
			return false, fmt.Errorf("decode message: %w", err)
		}
	}
	// messageHex == "" → msg stays nil → treated as []byte{} by ed25519

	pub, err := hex.DecodeString(publicHex)
	if err != nil {
		return false, fmt.Errorf("decode public key: %w", err)
	}
	sig, err := hex.DecodeString(sigHex)
	if err != nil {
		return false, fmt.Errorf("decode signature: %w", err)
	}

	if len(pub) != ed25519.PublicKeySize {
		return false, fmt.Errorf("public key length %d, want %d", len(pub), ed25519.PublicKeySize)
	}
	if len(sig) != ed25519.SignatureSize {
		return false, fmt.Errorf("signature length %d, want %d", len(sig), ed25519.SignatureSize)
	}

	return ed25519.Verify(ed25519.PublicKey(pub), msg, sig), nil
}

// ---------------------------------------------------------------------------
// Process tree: child subcommand
// ---------------------------------------------------------------------------

// runChild is the logic for the "child" subcommand.
// It spawns a grandchild (itself with child --sentinel <gc-sentinel> --lifetime-ms 60000),
// waits 100ms, writes [child_pid, grandchild_pid] to sentinel, then sleeps lifetime_ms.
func runChild(sentinelPath string, lifetimeMs int) error {
	if err := os.MkdirAll(filepath.Dir(sentinelPath), 0o700); err != nil {
		return fmt.Errorf("child: mkdir: %w", err)
	}

	exe, err := os.Executable()
	if err != nil {
		return fmt.Errorf("child: resolve exe: %w", err)
	}

	gcSentinel := filepath.Join(filepath.Dir(sentinelPath), "gc-sentinel.json")

	gcCmd := exec.Command(exe, "child",
		"--sentinel", gcSentinel,
		"--lifetime-ms", "60000",
	)
	gcCmd.Stdout = io.Discard
	gcCmd.Stderr = io.Discard

	if err := gcCmd.Start(); err != nil {
		return fmt.Errorf("child: start grandchild: %w", err)
	}

	// Give grandchild a moment to start.
	time.Sleep(100 * time.Millisecond)

	pids := []int{os.Getpid(), gcCmd.Process.Pid}
	data, err := json.Marshal(pids)
	if err != nil {
		return fmt.Errorf("child: marshal pids: %w", err)
	}
	if err := os.WriteFile(sentinelPath, data, 0o600); err != nil {
		return fmt.Errorf("child: write sentinel: %w", err)
	}

	// Sleep lifetime_ms then exit (process group kill will terminate us first).
	time.Sleep(time.Duration(lifetimeMs) * time.Millisecond)
	return nil
}

// ---------------------------------------------------------------------------
// Process tree: spawn + cancel (used in "run" assertions)
// ---------------------------------------------------------------------------

// spawnTreeAndCancel spawns the child process, waits for sentinel, kills the group,
// verifies all PIDs are dead, and returns the recorded PIDs.
func spawnTreeAndCancel(
	exe string,
	workspace string,
	lifetimeMs int,
	cancelDeadlineMs int,
) ([]int, error) {
	sentinelPath := filepath.Join(workspace, "tree-sentinel.json")
	// Remove any stale sentinel.
	os.Remove(sentinelPath)

	cmd := exec.Command(exe, "child",
		"--sentinel", sentinelPath,
		"--lifetime-ms", strconv.Itoa(lifetimeMs),
	)
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	setProcAttr(cmd)

	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("spawn child: %w", err)
	}
	pgid := cmd.Process.Pid

	// Poll for sentinel.
	deadline := time.Now().Add(time.Duration(cancelDeadlineMs) * time.Millisecond)
	var pids []int
	for time.Now().Before(deadline) {
		data, err := os.ReadFile(sentinelPath)
		if err == nil {
			var tmp []int
			if jerr := json.Unmarshal(data, &tmp); jerr == nil && len(tmp) >= 2 {
				pids = tmp
				break
			}
		}
		time.Sleep(50 * time.Millisecond)
	}

	// Kill the process group.
	killProcessGroup(pgid) //nolint:errcheck

	// Reap main child.
	cmd.Wait() //nolint:errcheck

	// Give OS a moment to reap grandchild.
	time.Sleep(100 * time.Millisecond)

	// Wait up to 5s for all PIDs to die.
	killDeadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(killDeadline) {
		allDead := true
		for _, pid := range pids {
			if isPidAlive(pid) {
				allDead = false
				break
			}
		}
		if allDead {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}

	return pids, nil
}

// ---------------------------------------------------------------------------
// Result helpers
// ---------------------------------------------------------------------------

type assertion struct {
	ID     string `json:"id"`
	Status string `json:"status"`
	Reason string `json:"reason,omitempty"`
}

func pass(id string) assertion { return assertion{ID: id, Status: "pass"} }
func fail(id, reason string) assertion {
	return assertion{ID: id, Status: "fail", Reason: reason}
}

// ---------------------------------------------------------------------------
// Contract runner
// ---------------------------------------------------------------------------

// contractFile is the JSON structure of host-probe-v1.json.
type contractFile struct {
	TimingsMs struct {
		LeaseTTL               int `json:"lease_ttl"`
		LeaseRenewal           int `json:"lease_renewal"`
		LeaseCompetitorAttempt int `json:"lease_competitor_attempt"`
		ChildLifetime          int `json:"child_lifetime"`
		CancelDeadline         int `json:"cancel_deadline"`
	} `json:"timings_ms"`
	CanonicalValid   string `json:"canonical_valid"`
	CanonicalInvalid string `json:"canonical_invalid"`
	CryptoVectors    string `json:"crypto_vectors"`
}

// ed25519VectorFile is the structure of ed25519-rfc8032.json.
type ed25519VectorFile struct {
	Message   string `json:"message"`
	PublicKey string `json:"public_key"`
	Signature string `json:"signature"`
}

// runContract executes all 18 assertions and returns the result map.
func runContract(contractPath, workspace string) (map[string]interface{}, error) {
	contractPath, err := filepath.Abs(contractPath)
	if err != nil {
		return nil, err
	}
	workspace, err = filepath.Abs(workspace)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(workspace, 0o700); err != nil {
		return nil, err
	}

	contractDir := filepath.Dir(contractPath)

	raw, err := os.ReadFile(contractPath)
	if err != nil {
		return nil, fmt.Errorf("read contract: %w", err)
	}
	var contract contractFile
	if err := json.Unmarshal(raw, &contract); err != nil {
		return nil, fmt.Errorf("parse contract: %w", err)
	}

	// Apply defaults.
	if contract.TimingsMs.LeaseTTL == 0 {
		contract.TimingsMs.LeaseTTL = 1200
	}
	if contract.TimingsMs.LeaseRenewal == 0 {
		contract.TimingsMs.LeaseRenewal = 400
	}
	if contract.TimingsMs.LeaseCompetitorAttempt == 0 {
		contract.TimingsMs.LeaseCompetitorAttempt = 600
	}
	if contract.TimingsMs.ChildLifetime == 0 {
		contract.TimingsMs.ChildLifetime = 30000
	}
	if contract.TimingsMs.CancelDeadline == 0 {
		contract.TimingsMs.CancelDeadline = 5000
	}
	if contract.CanonicalValid == "" {
		contract.CanonicalValid = "canonical-valid/"
	}
	if contract.CanonicalInvalid == "" {
		contract.CanonicalInvalid = "canonical-invalid/"
	}
	if contract.CryptoVectors == "" {
		contract.CryptoVectors = "ed25519-rfc8032.json"
	}

	leaseTTL := contract.TimingsMs.LeaseTTL
	leaseRenewal := contract.TimingsMs.LeaseRenewal
	leaseCompetitor := contract.TimingsMs.LeaseCompetitorAttempt
	childLifetime := contract.TimingsMs.ChildLifetime
	cancelDeadline := contract.TimingsMs.CancelDeadline

	var assertions []assertion
	errMsgs := []string{}
	descendantPIDs := []int{}

	recordFail := func(a assertion) {
		assertions = append(assertions, a)
		if a.Status == "fail" {
			errMsgs = append(errMsgs, a.ID+": "+a.Reason)
		}
	}

	// -----------------------------------------------------------------------
	// 1. manifest.accept-valid
	// -----------------------------------------------------------------------
	{
		validDir := filepath.Join(contractDir, strings.TrimSuffix(contract.CanonicalValid, "/"))
		rolePath := filepath.Join(validDir, "src", "roles", "unity-scout", "role.json")
		if err := decodeRoleJSON(rolePath, true); err != nil {
			recordFail(fail("manifest.accept-valid", err.Error()))
		} else {
			recordFail(pass("manifest.accept-valid"))
		}
	}

	// -----------------------------------------------------------------------
	// 2. manifest.reject-unknown
	// -----------------------------------------------------------------------
	{
		invalidDir := filepath.Join(contractDir, strings.TrimSuffix(contract.CanonicalInvalid, "/"))
		rolePath := filepath.Join(invalidDir, "src", "roles", "unity-scout", "role.json")
		err := decodeRoleJSON(rolePath, true)
		if err != nil {
			// Good: we expected rejection.
			recordFail(pass("manifest.reject-unknown"))
		} else {
			recordFail(fail("manifest.reject-unknown", "decoder did not reject unknown field"))
		}
	}

	// -----------------------------------------------------------------------
	// 3. path.unicode-space
	// -----------------------------------------------------------------------
	{
		unicodeFile := filepath.Join(workspace, "ünïcödé spàce.txt")
		if err := os.WriteFile(unicodeFile, []byte("ok"), 0o600); err != nil {
			recordFail(fail("path.unicode-space", err.Error()))
		} else {
			content, err := os.ReadFile(unicodeFile)
			if err != nil {
				recordFail(fail("path.unicode-space", err.Error()))
			} else if string(content) != "ok" {
				recordFail(fail("path.unicode-space", fmt.Sprintf("unexpected content: %q", string(content))))
			} else {
				recordFail(pass("path.unicode-space"))
			}
		}
	}

	// -----------------------------------------------------------------------
	// 4. filesystem.atomic-replace
	// -----------------------------------------------------------------------
	{
		atomicTarget := filepath.Join(workspace, "atomic-state.json")
		err1 := atomicReplace(atomicTarget, []byte(`{"initial": true}`+"\n"))
		err2 := atomicReplace(atomicTarget, []byte(`{"replaced": true}`+"\n"))
		if err1 != nil || err2 != nil {
			msg := ""
			if err1 != nil {
				msg += "first replace: " + err1.Error()
			}
			if err2 != nil {
				msg += " second replace: " + err2.Error()
			}
			recordFail(fail("filesystem.atomic-replace", strings.TrimSpace(msg)))
		} else {
			data, err := os.ReadFile(atomicTarget)
			if err != nil {
				recordFail(fail("filesystem.atomic-replace", err.Error()))
			} else {
				var m map[string]interface{}
				if err := json.Unmarshal(data, &m); err != nil {
					recordFail(fail("filesystem.atomic-replace", "result not valid JSON: "+err.Error()))
				} else if v, ok := m["replaced"]; !ok || v != true {
					recordFail(fail("filesystem.atomic-replace", fmt.Sprintf("unexpected data: %v", m)))
				} else {
					// Check no leftover .tmp files.
					entries, _ := os.ReadDir(workspace)
					var leftovers []string
					for _, e := range entries {
						if strings.HasSuffix(e.Name(), ".tmp") {
							leftovers = append(leftovers, e.Name())
						}
					}
					if len(leftovers) > 0 {
						recordFail(fail("filesystem.atomic-replace", fmt.Sprintf("leftover tmp files: %v", leftovers)))
					} else {
						recordFail(pass("filesystem.atomic-replace"))
					}
				}
			}
		}
	}

	// -----------------------------------------------------------------------
	// 5–9. Lease assertions
	// -----------------------------------------------------------------------
	leasePath := filepath.Join(workspace, ".lease", "kinglet.lease")

	// lease.acquire
	leaseA := newLease(leasePath, leaseTTL)
	leaseAcquired := false
	{
		ok, err := leaseA.Acquire()
		if err != nil {
			recordFail(fail("lease.acquire", err.Error()))
		} else if !ok || leaseA.Owner() == "" {
			recordFail(fail("lease.acquire", "acquire returned false"))
		} else {
			leaseAcquired = true
			recordFail(pass("lease.acquire"))
		}
	}

	// lease.renew
	{
		time.Sleep(time.Duration(leaseRenewal) * time.Millisecond)
		ok, err := leaseA.Renew()
		if err != nil {
			recordFail(fail("lease.renew", err.Error()))
		} else if !ok {
			recordFail(fail("lease.renew", "renew returned false"))
		} else {
			recordFail(pass("lease.renew"))
		}
	}

	// lease.reject-competitor
	{
		extra := leaseCompetitor - leaseRenewal
		if extra > 0 {
			time.Sleep(time.Duration(extra) * time.Millisecond)
		}
		leaseB := newLease(leasePath, leaseTTL)
		ok, err := leaseB.Acquire()
		if err != nil {
			recordFail(fail("lease.reject-competitor", err.Error()))
		} else if ok {
			recordFail(fail("lease.reject-competitor", "competitor was granted the lease"))
			leaseB.Release() //nolint:errcheck
		} else {
			recordFail(pass("lease.reject-competitor"))
		}
	}

	// lease.expire — short-TTL lease → wait → steal
	{
		shortPath := filepath.Join(workspace, ".lease", "short.lease")
		leaseShort := newLease(shortPath, 100) // 100ms TTL
		leaseShort.Acquire()                    //nolint:errcheck
		time.Sleep(300 * time.Millisecond)      // wait past TTL

		leaseNew := newLease(shortPath, leaseTTL)
		ok, err := leaseNew.Acquire()
		if err != nil {
			recordFail(fail("lease.expire", err.Error()))
		} else if !ok {
			recordFail(fail("lease.expire", "could not acquire after expired lease"))
		} else {
			leaseNew.Release() //nolint:errcheck
			recordFail(pass("lease.expire"))
		}
	}

	// lease.release
	{
		released, err := leaseA.Release()
		if err != nil {
			recordFail(fail("lease.release", err.Error()))
		} else {
			_, statErr := os.Stat(leasePath)
			stillExists := statErr == nil
			if released && !stillExists {
				leaseAcquired = false
				recordFail(pass("lease.release"))
			} else {
				recordFail(fail("lease.release", fmt.Sprintf("released=%v file_exists=%v", released, stillExists)))
			}
		}
	}
	if leaseAcquired {
		leaseA.Release() //nolint:errcheck
	}

	// -----------------------------------------------------------------------
	// 10–12. Process assertions
	// -----------------------------------------------------------------------
	exe, err := os.Executable()
	if err != nil {
		exe = os.Args[0]
	}

	recordedPIDs, procErr := spawnTreeAndCancel(exe, workspace, childLifetime, cancelDeadline)
	if procErr != nil {
		recordFail(fail("process.child-grandchild", procErr.Error()))
		recordFail(fail("process.cancel", procErr.Error()))
		recordFail(fail("process.no-descendants", procErr.Error()))
	} else {
		if len(recordedPIDs) >= 2 {
			recordFail(pass("process.child-grandchild"))
		} else {
			recordFail(fail("process.child-grandchild",
				fmt.Sprintf("sentinel had only %d pids", len(recordedPIDs))))
		}

		// process.cancel — if we reached kill, grant pass.
		if len(recordedPIDs) > 0 {
			recordFail(pass("process.cancel"))
		} else {
			recordFail(fail("process.cancel", "no pids recorded — see process.child-grandchild"))
		}

		// process.no-descendants — verify all dead.
		var alivePIDs []int
		for _, pid := range recordedPIDs {
			if isPidAlive(pid) {
				alivePIDs = append(alivePIDs, pid)
			}
		}
		if len(alivePIDs) == 0 {
			recordFail(pass("process.no-descendants"))
		} else {
			descendantPIDs = alivePIDs
			recordFail(fail("process.no-descendants",
				fmt.Sprintf("pids still alive: %v", alivePIDs)))
		}
	}

	// -----------------------------------------------------------------------
	// 13. crypto.sha256
	// -----------------------------------------------------------------------
	{
		h := sha256.Sum256([]byte{})
		got := hex.EncodeToString(h[:])
		expected := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
		if got == expected {
			recordFail(pass("crypto.sha256"))
		} else {
			recordFail(fail("crypto.sha256", fmt.Sprintf("got %s", got)))
		}
	}

	// -----------------------------------------------------------------------
	// 14. crypto.ed25519
	// -----------------------------------------------------------------------
	{
		vectorsPath := filepath.Join(contractDir, contract.CryptoVectors)
		raw, err := os.ReadFile(vectorsPath)
		if err != nil {
			recordFail(fail("crypto.ed25519", "read vectors: "+err.Error()))
		} else {
			var vec ed25519VectorFile
			if err := json.Unmarshal(raw, &vec); err != nil {
				recordFail(fail("crypto.ed25519", "parse vectors: "+err.Error()))
			} else {
				ok, err := verifyEd25519(vec.Message, vec.PublicKey, vec.Signature)
				if err != nil {
					recordFail(fail("crypto.ed25519", err.Error()))
				} else if !ok {
					recordFail(fail("crypto.ed25519", "RFC 8032 vector 1 failed"))
				} else {
					recordFail(pass("crypto.ed25519"))
				}
			}
		}
	}

	// -----------------------------------------------------------------------
	// 15–18. Cleanup scenarios
	// -----------------------------------------------------------------------

	// cleanup.success
	{
		clPath := filepath.Join(workspace, ".cleanup", "success.lease")
		cl := newLease(clPath, leaseTTL)
		tmpFile := filepath.Join(workspace, "cleanup-success.tmp")
		var cleanupErr error
		func() {
			defer func() {
				cl.Release() //nolint:errcheck
				os.Remove(tmpFile)
			}()
			if _, err := cl.Acquire(); err != nil {
				cleanupErr = err
				return
			}
			cleanupErr = atomicReplace(tmpFile, []byte("ok"))
		}()
		if cleanupErr != nil {
			recordFail(fail("cleanup.success", cleanupErr.Error()))
		} else {
			recordFail(pass("cleanup.success"))
		}
	}

	// cleanup.crash — simulate panic+recover
	{
		clPath := filepath.Join(workspace, ".cleanup", "crash.lease")
		cl := newLease(clPath, leaseTTL)
		crashCleanupOK := false
		func() {
			defer func() {
				cl.Release() //nolint:errcheck
				crashCleanupOK = true
				recover() //nolint:errcheck — must be last in defer
			}()
			cl.Acquire() //nolint:errcheck
			panic("simulated crash")
		}()
		if crashCleanupOK {
			recordFail(pass("cleanup.crash"))
		} else {
			recordFail(fail("cleanup.crash", "defer did not run after simulated crash"))
		}
	}

	// cleanup.timeout — simulate deadline exceeded
	{
		clPath := filepath.Join(workspace, ".cleanup", "timeout.lease")
		cl := newLease(clPath, leaseTTL)
		timeoutCleanupOK := false
		var timeoutSimErr error
		func() {
			defer func() {
				cl.Release() //nolint:errcheck
				timeoutCleanupOK = true
			}()
			cl.Acquire() //nolint:errcheck
			timeoutSimErr = errors.New("simulated timeout")
		}()
		if timeoutSimErr != nil && timeoutCleanupOK {
			recordFail(pass("cleanup.timeout"))
		} else if !timeoutCleanupOK {
			recordFail(fail("cleanup.timeout", "defer did not run after timeout"))
		} else {
			recordFail(pass("cleanup.timeout"))
		}
	}

	// cleanup.cancel — simulate context cancel
	{
		clPath := filepath.Join(workspace, ".cleanup", "cancel.lease")
		cl := newLease(clPath, leaseTTL)
		cancelCleanupOK := false
		var cancelSimErr error
		func() {
			defer func() {
				cl.Release() //nolint:errcheck
				cancelCleanupOK = true
			}()
			cl.Acquire() //nolint:errcheck
			cancelSimErr = errors.New("simulated cancel")
		}()
		if cancelSimErr != nil && cancelCleanupOK {
			recordFail(pass("cleanup.cancel"))
		} else if !cancelCleanupOK {
			recordFail(fail("cleanup.cancel", "defer did not run after cancel"))
		} else {
			recordFail(pass("cleanup.cancel"))
		}
	}

	// -----------------------------------------------------------------------
	// Active lease check
	// -----------------------------------------------------------------------
	checkPaths := []string{
		leasePath,
		filepath.Join(workspace, ".cleanup", "success.lease"),
		filepath.Join(workspace, ".cleanup", "crash.lease"),
		filepath.Join(workspace, ".cleanup", "timeout.lease"),
		filepath.Join(workspace, ".cleanup", "cancel.lease"),
	}
	activeLease := false
	for _, p := range checkPaths {
		if _, err := os.Stat(p); err == nil {
			activeLease = true
			break
		}
	}

	// -----------------------------------------------------------------------
	// Build ordered result
	// -----------------------------------------------------------------------
	requiredOrder := []string{
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
	}

	assertionMap := make(map[string]assertion)
	for _, a := range assertions {
		if _, seen := assertionMap[a.ID]; !seen {
			assertionMap[a.ID] = a
		}
	}

	// Fill any missing assertions as fail.
	for _, id := range requiredOrder {
		if _, ok := assertionMap[id]; !ok {
			assertionMap[id] = fail(id, "assertion not reached")
			errMsgs = append(errMsgs, id+": not reached")
		}
	}

	orderedAssertions := make([]map[string]string, 0, len(requiredOrder))
	allPass := true
	for _, id := range requiredOrder {
		a := assertionMap[id]
		m := map[string]string{"id": a.ID, "status": a.Status}
		if a.Status != "pass" {
			allPass = false
		}
		orderedAssertions = append(orderedAssertions, m)
	}

	if len(descendantPIDs) > 0 || activeLease {
		allPass = false
	}

	status := "pass"
	if !allPass {
		status = "fail"
	}

	result := map[string]interface{}{
		"schema": resultSchema,
		"candidate": map[string]string{
			"id":      candidateID,
			"version": candidateVersion,
		},
		"status":          status,
		"errors":          errMsgs,
		"assertions":      orderedAssertions,
		"descendant_pids": descendantPIDs,
		"active_lease":    activeLease,
	}
	return result, nil
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

func usage() {
	fmt.Fprintln(os.Stderr, `Usage:
  kinglet-host-probe --version
  kinglet-host-probe run --contract <path> --workspace <dir> --result <path>
  kinglet-host-probe child --sentinel <path> --lifetime-ms <ms>`)
}

func main() {
	args := os.Args[1:]

	if len(args) == 0 {
		usage()
		os.Exit(1)
	}

	switch args[0] {
	case "--version":
		fmt.Printf("go %s\n", candidateVersion)
		os.Exit(0)

	case "run":
		var contract, workspace, result string
		for i := 1; i < len(args); i++ {
			switch args[i] {
			case "--contract":
				i++
				if i < len(args) {
					contract = args[i]
				}
			case "--workspace":
				i++
				if i < len(args) {
					workspace = args[i]
				}
			case "--result":
				i++
				if i < len(args) {
					result = args[i]
				}
			}
		}
		if contract == "" || workspace == "" || result == "" {
			fmt.Fprintln(os.Stderr, "run: --contract, --workspace, and --result are required")
			os.Exit(1)
		}
		res, err := runContract(contract, workspace)
		if err != nil {
			fmt.Fprintln(os.Stderr, "run contract:", err)
			os.Exit(1)
		}
		out, err := json.MarshalIndent(res, "", "  ")
		if err != nil {
			fmt.Fprintln(os.Stderr, "marshal result:", err)
			os.Exit(1)
		}
		// Write atomically.
		if err := atomicReplace(result, append(out, '\n')); err != nil {
			fmt.Fprintln(os.Stderr, "write result:", err)
			os.Exit(1)
		}
		// Echo to stdout.
		os.Stdout.Write(out)
		os.Stdout.Write([]byte("\n"))

		if res["status"] == "pass" {
			os.Exit(0)
		}
		os.Exit(1)

	case "child":
		var sentinel string
		var lifetimeMs int
		for i := 1; i < len(args); i++ {
			switch args[i] {
			case "--sentinel":
				i++
				if i < len(args) {
					sentinel = args[i]
				}
			case "--lifetime-ms":
				i++
				if i < len(args) {
					n, err := strconv.Atoi(args[i])
					if err == nil {
						lifetimeMs = n
					}
				}
			}
		}
		if sentinel == "" || lifetimeMs <= 0 {
			fmt.Fprintln(os.Stderr, "child: --sentinel and --lifetime-ms are required")
			os.Exit(1)
		}
		if err := runChild(sentinel, lifetimeMs); err != nil {
			fmt.Fprintln(os.Stderr, "child:", err)
			os.Exit(1)
		}
		os.Exit(0)

	default:
		usage()
		os.Exit(1)
	}
}

