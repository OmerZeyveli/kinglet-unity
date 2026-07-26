package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// ---------------------------------------------------------------------------
// atomicReplace tests
// ---------------------------------------------------------------------------

func TestAtomicReplace_CreatesFile(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "out.json")

	if err := atomicReplace(target, []byte(`{"ok":true}`)); err != nil {
		t.Fatalf("atomicReplace: %v", err)
	}

	data, err := os.ReadFile(target)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if string(data) != `{"ok":true}` {
		t.Errorf("unexpected content: %q", string(data))
	}
}

func TestAtomicReplace_NoLeftoverTmpFiles(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "state.json")

	for i := 0; i < 3; i++ {
		if err := atomicReplace(target, []byte(`{"i":true}`)); err != nil {
			t.Fatalf("atomicReplace iter %d: %v", i, err)
		}
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("readdir: %v", err)
	}
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".tmp") {
			t.Errorf("leftover tmp file: %s", e.Name())
		}
	}
}

func TestAtomicReplace_UnicodeSpacePath(t *testing.T) {
	// The workspace itself contains unicode and a space — matches path.unicode-space assertion.
	dir := t.TempDir() + "/Kral Yalıçapkını"
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	target := filepath.Join(dir, "data.json")
	payload := []byte(`{"unicode":true}`)

	if err := atomicReplace(target, payload); err != nil {
		t.Fatalf("atomicReplace: %v", err)
	}
	got, err := os.ReadFile(target)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if string(got) != string(payload) {
		t.Errorf("content mismatch: got %q want %q", string(got), string(payload))
	}

	// No leftover .tmp files in that directory.
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".tmp") {
			t.Errorf("leftover tmp file: %s", e.Name())
		}
	}
}

func TestAtomicReplace_Overwrites(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "state.json")

	if err := atomicReplace(target, []byte(`{"v":1}`)); err != nil {
		t.Fatal(err)
	}
	if err := atomicReplace(target, []byte(`{"v":2}`)); err != nil {
		t.Fatal(err)
	}

	data, _ := os.ReadFile(target)
	var m map[string]interface{}
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatal(err)
	}
	if m["v"].(float64) != 2 {
		t.Errorf("expected v=2 after overwrite, got %v", m["v"])
	}
}

// ---------------------------------------------------------------------------
// Lease tests
// ---------------------------------------------------------------------------

func TestLease_AcquireAndRelease(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "test.lease")

	l := newLease(path, 2000)
	ok, err := l.Acquire()
	if err != nil || !ok {
		t.Fatalf("acquire: ok=%v err=%v", ok, err)
	}
	if l.Owner() == "" {
		t.Fatal("owner should be set after acquire")
	}

	rel, err := l.Release()
	if err != nil || !rel {
		t.Fatalf("release: rel=%v err=%v", rel, err)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Error("lease file should be gone after release")
	}
}

func TestLease_SecondOwnerCannotAcquireLiveLease(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "test.lease")

	a := newLease(path, 2000)
	ok, err := a.Acquire()
	if err != nil || !ok {
		t.Fatalf("first acquire: ok=%v err=%v", ok, err)
	}
	defer a.Release() //nolint:errcheck

	b := newLease(path, 2000)
	ok2, err2 := b.Acquire()
	if err2 != nil {
		t.Fatalf("second acquire unexpected error: %v", err2)
	}
	if ok2 {
		t.Error("second owner should NOT have acquired a live lease")
	}
}

func TestLease_ExpiredLeaseCanBeStolen(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "test.lease")

	short := newLease(path, 100) // 100ms TTL
	ok, err := short.Acquire()
	if err != nil || !ok {
		t.Fatalf("short acquire: ok=%v err=%v", ok, err)
	}

	// Wait well past TTL.
	time.Sleep(300 * time.Millisecond)

	stealer := newLease(path, 2000)
	ok2, err2 := stealer.Acquire()
	if err2 != nil {
		t.Fatalf("stealer acquire error: %v", err2)
	}
	if !ok2 {
		t.Error("should have acquired expired lease")
	}
	stealer.Release() //nolint:errcheck
}

func TestLease_Renew(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "test.lease")

	l := newLease(path, 2000)
	ok, err := l.Acquire()
	if err != nil || !ok {
		t.Fatalf("acquire: ok=%v err=%v", ok, err)
	}
	defer l.Release() //nolint:errcheck

	ok2, err2 := l.Renew()
	if err2 != nil || !ok2 {
		t.Fatalf("renew: ok=%v err=%v", ok2, err2)
	}
}

func TestLease_RenewFailsWithoutPriorAcquire(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "test.lease")

	l := newLease(path, 2000)
	ok, err := l.Renew()
	if err != nil {
		t.Fatalf("renew without owner gave unexpected error: %v", err)
	}
	if ok {
		t.Error("renew without prior acquire should return false")
	}
}

// ---------------------------------------------------------------------------
// Ed25519 tests
// ---------------------------------------------------------------------------

func TestVerifyEd25519_RFC8032Vector1(t *testing.T) {
	// RFC 8032 Section 5.1 Test Vector 1.
	// message is empty string "" → empty bytes.
	const (
		msgHex = "" // empty string → empty bytes
		pubHex = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
		sigHex = "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
	)
	ok, err := verifyEd25519(msgHex, pubHex, sigHex)
	if err != nil {
		t.Fatalf("verifyEd25519: %v", err)
	}
	if !ok {
		t.Error("RFC 8032 vector 1 should verify successfully")
	}
}

func TestVerifyEd25519_TamperedSignatureFails(t *testing.T) {
	const (
		pubHex = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
		// Last byte of sig changed from 0b → 0c.
		sigHex = "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100c"
	)
	ok, err := verifyEd25519("", pubHex, sigHex)
	if err != nil {
		t.Fatalf("unexpected error on tampered sig: %v", err)
	}
	if ok {
		t.Error("tampered signature should not verify")
	}
}

// ---------------------------------------------------------------------------
// SHA256 tests
// ---------------------------------------------------------------------------

func TestSHA256_EmptyInput(t *testing.T) {
	h := sha256.Sum256([]byte{})
	got := hex.EncodeToString(h[:])
	const want = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
	if got != want {
		t.Errorf("SHA256('') = %s; want %s", got, want)
	}
}

func TestSHA256_KnownInput(t *testing.T) {
	h := sha256.Sum256([]byte("abc"))
	got := hex.EncodeToString(h[:])
	// SHA256 of "abc".
	const want = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
	if got != want {
		t.Errorf("SHA256('abc') = %s; want %s", got, want)
	}
}

// ---------------------------------------------------------------------------
// Manifest decode tests
// ---------------------------------------------------------------------------

func TestDecodeRoleJSON_ValidAccepted(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "role.json")
	valid := `{"schema_version":1,"id":"role.test","kind":"role","name":"Test Role","summary":"A test role."}`
	if err := os.WriteFile(path, []byte(valid), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := decodeRoleJSON(path, true); err != nil {
		t.Errorf("valid role rejected: %v", err)
	}
}

func TestDecodeRoleJSON_UnknownFieldRejected(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "role.json")
	invalid := `{"schema_version":1,"id":"role.test","kind":"role","name":"Test Role","summary":"A test role.","unknown":true}`
	if err := os.WriteFile(path, []byte(invalid), 0o600); err != nil {
		t.Fatal(err)
	}
	err := decodeRoleJSON(path, true)
	if err == nil {
		t.Error("expected error for unknown field, got nil")
	}
}
