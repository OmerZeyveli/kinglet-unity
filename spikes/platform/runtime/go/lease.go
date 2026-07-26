package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// leaseRecord is the JSON structure stored in the lease file.
type leaseRecord struct {
	Owner      string `json:"owner"`
	ExpiresUTC string `json:"expires_utc"`
}

// Lease is an exclusive advisory lease backed by a JSON file.
// The file stores {"owner": "<hex>", "expires_utc": "<RFC3339Nano>"}.
type Lease struct {
	path   string
	ttlMs  int
	owner  string // empty when not held
}

// newLease creates a Lease for the given file path and TTL.
func newLease(path string, ttlMs int) *Lease {
	return &Lease{path: path, ttlMs: ttlMs}
}

// Owner returns the owner hex string for this lease instance, or "".
func (l *Lease) Owner() string { return l.owner }

// generateOwner returns 16 random bytes encoded as a 32-char hex string.
func generateOwner() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generate owner: %w", err)
	}
	return hex.EncodeToString(b), nil
}

// expiry returns the expiry time for a new lease record.
func (l *Lease) expiry() time.Time {
	return time.Now().UTC().Add(time.Duration(l.ttlMs) * time.Millisecond)
}

// encode serialises the lease payload.
func (l *Lease) encode() ([]byte, error) {
	rec := leaseRecord{
		Owner:      l.owner,
		ExpiresUTC: l.expiry().Format(time.RFC3339Nano),
	}
	return json.Marshal(rec)
}

// readRecord reads the lease file and returns the parsed record.
// Returns (nil, nil) when the file does not exist.
// Returns a zero-value record with an error on parse failures.
func (l *Lease) readRecord() (*leaseRecord, error) {
	data, err := os.ReadFile(l.path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, nil
		}
		return nil, err
	}
	var rec leaseRecord
	if err := json.Unmarshal(data, &rec); err != nil {
		return nil, fmt.Errorf("parse lease: %w", err)
	}
	if rec.Owner == "" || rec.ExpiresUTC == "" {
		return nil, fmt.Errorf("malformed lease: missing fields")
	}
	return &rec, nil
}

// isExpired reports whether the lease record has passed its expiry time.
func isExpired(rec *leaseRecord) bool {
	exp, err := time.Parse(time.RFC3339Nano, rec.ExpiresUTC)
	if err != nil {
		// Malformed expiry → treat as expired so we don't block forever.
		return true
	}
	return time.Now().UTC().After(exp)
}

// Acquire tries to acquire the lease. Returns true on success, false if busy.
func (l *Lease) Acquire() (bool, error) {
	if err := os.MkdirAll(filepath.Dir(l.path), 0o700); err != nil {
		return false, fmt.Errorf("acquire: mkdir: %w", err)
	}

	owner, err := generateOwner()
	if err != nil {
		return false, err
	}

	rec := leaseRecord{
		Owner:      owner,
		ExpiresUTC: l.expiry().Format(time.RFC3339Nano),
	}
	payload, err := json.Marshal(rec)
	if err != nil {
		return false, fmt.Errorf("acquire: marshal: %w", err)
	}

	// O_CREATE|O_EXCL — atomic exclusive create.
	f, err := os.OpenFile(l.path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err == nil {
		// Success: write payload and close.
		if _, werr := f.Write(payload); werr != nil {
			f.Close()
			os.Remove(l.path)
			return false, fmt.Errorf("acquire: write: %w", werr)
		}
		if serr := f.Sync(); serr != nil {
			f.Close()
			os.Remove(l.path)
			return false, fmt.Errorf("acquire: sync: %w", serr)
		}
		f.Close()
		l.owner = owner
		return true, nil
	}

	if !errors.Is(err, os.ErrExist) {
		return false, fmt.Errorf("acquire: open: %w", err)
	}

	// File exists. Read and check expiry.
	existing, rerr := l.readRecord()
	if rerr != nil || existing == nil {
		// Unreadable or gone — busy (or retry on gone, but let's be safe).
		return false, nil
	}
	if !isExpired(existing) {
		return false, nil // busy
	}

	// Expired — steal it.
	if rerr := os.Remove(l.path); rerr != nil && !errors.Is(rerr, os.ErrNotExist) {
		return false, nil // couldn't remove; treat as busy
	}
	return l.Acquire() // retry after removal
}

// Renew refreshes the lease expiry. Only succeeds if this instance owns it.
func (l *Lease) Renew() (bool, error) {
	if l.owner == "" {
		return false, nil
	}
	rec, err := l.readRecord()
	if err != nil || rec == nil || rec.Owner != l.owner {
		return false, nil
	}
	payload, err := l.encode()
	if err != nil {
		return false, fmt.Errorf("renew: encode: %w", err)
	}
	if err := atomicReplace(l.path, payload); err != nil {
		return false, fmt.Errorf("renew: atomic replace: %w", err)
	}
	return true, nil
}

// Release removes the lease file if this instance owns it.
func (l *Lease) Release() (bool, error) {
	if l.owner == "" {
		return false, nil
	}
	rec, err := l.readRecord()
	if err == nil && rec != nil && rec.Owner == l.owner {
		if rerr := os.Remove(l.path); rerr != nil && !errors.Is(rerr, os.ErrNotExist) {
			l.owner = ""
			return false, fmt.Errorf("release: remove: %w", rerr)
		}
		l.owner = ""
		return true, nil
	}
	l.owner = ""
	return false, nil
}

// IsActive returns true when the lease file exists (regardless of owner).
func (l *Lease) IsActive() bool {
	_, err := os.Stat(l.path)
	return err == nil
}
