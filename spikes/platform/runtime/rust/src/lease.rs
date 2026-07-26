//! File-backed exclusive advisory lease for the Rust host probe candidate.
//!
//! A lease is a JSON file `{"owner": "<uuid>", "expires_utc": "<rfc3339-utc>"}`
//! created with `OpenOptions::create_new(true)` so acquisition is atomic:
//! exactly one competitor can create the file. A live (unexpired) lease held by
//! another owner rejects competitors; an expired lease can be stolen.

use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Serialised lease record.
#[derive(Debug, Serialize, Deserialize)]
struct LeaseRecord {
    owner: String,
    /// Milliseconds since the Unix epoch (UTC). Stored as a string to keep the
    /// on-disk shape stable and human-readable.
    expires_utc: String,
    /// Absolute expiry as epoch milliseconds — the authoritative value we
    /// compare against. `expires_utc` is the display form of the same instant.
    expires_epoch_ms: u128,
}

/// An exclusive advisory lease backed by a single JSON file.
pub struct Lease {
    path: PathBuf,
    ttl_ms: u64,
    /// Owner UUID for this handle; `None` until this handle holds the lease.
    owner: Option<String>,
}

/// Current wall-clock time as epoch milliseconds (UTC).
fn now_epoch_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
}

/// Render an epoch-millisecond instant as an RFC 3339-ish UTC string.
/// Kept dependency-free: a stable, sortable, unambiguous UTC display form.
fn format_utc(epoch_ms: u128) -> String {
    let secs = (epoch_ms / 1000) as u64;
    let millis = (epoch_ms % 1000) as u32;
    // Days since epoch and time-of-day, civil calendar (proleptic Gregorian).
    let days = (secs / 86_400) as i64;
    let tod = secs % 86_400;
    let (hh, mm, ss) = (tod / 3600, (tod % 3600) / 60, tod % 60);

    // days -> y/m/d via Howard Hinnant's civil_from_days.
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as i64;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if m <= 2 { y + 1 } else { y };

    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}.{:03}Z",
        year, m, d, hh, mm, ss, millis
    )
}

impl Lease {
    /// Create a lease handle for `path` with a time-to-live of `ttl_ms`.
    pub fn new<P: AsRef<Path>>(path: P, ttl_ms: u64) -> Self {
        Lease {
            path: path.as_ref().to_path_buf(),
            ttl_ms,
            owner: None,
        }
    }

    /// The owner UUID of this handle, once acquired.
    pub fn owner(&self) -> Option<&str> {
        self.owner.as_deref()
    }

    /// Whether a lease file currently exists on disk (regardless of owner/expiry).
    #[allow(dead_code)]
    pub fn is_active(&self) -> bool {
        self.path.exists()
    }

    fn read_record(&self) -> io::Result<Option<LeaseRecord>> {
        match fs::read(&self.path) {
            Ok(bytes) => match serde_json::from_slice::<LeaseRecord>(&bytes) {
                Ok(rec) => Ok(Some(rec)),
                Err(e) => Err(io::Error::new(io::ErrorKind::InvalidData, e)),
            },
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(e),
        }
    }

    fn write_new_owned(&mut self, owner: &str) -> io::Result<()> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)?;
        }
        let expires_ms = now_epoch_ms() + self.ttl_ms as u128;
        let rec = LeaseRecord {
            owner: owner.to_string(),
            expires_utc: format_utc(expires_ms),
            expires_epoch_ms: expires_ms,
        };
        let payload = serde_json::to_vec(&rec)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

        // Exclusive create: fails with AlreadyExists if a competitor holds it.
        let mut f: File = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&self.path)?;
        f.write_all(&payload)?;
        f.sync_all()?;
        self.owner = Some(owner.to_string());
        Ok(())
    }

    /// Try to acquire the lease.
    ///
    /// Returns `Ok(true)` when this handle now holds the lease, `Ok(false)` when
    /// a live lease is held by someone else. An expired foreign lease is stolen.
    pub fn acquire(&mut self) -> io::Result<bool> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)?;
        }
        let owner = Uuid::new_v4().to_string();

        match self.write_new_owned(&owner) {
            Ok(()) => Ok(true),
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => {
                // Someone holds it — inspect expiry.
                match self.read_record()? {
                    None => {
                        // Vanished between create and read; retry once.
                        match self.write_new_owned(&owner) {
                            Ok(()) => Ok(true),
                            Err(e2) if e2.kind() == io::ErrorKind::AlreadyExists => Ok(false),
                            Err(e2) => Err(e2),
                        }
                    }
                    Some(rec) => {
                        if now_epoch_ms() <= rec.expires_epoch_ms {
                            // Live foreign lease — reject.
                            Ok(false)
                        } else {
                            // Expired — steal it: remove then recreate exclusively.
                            match fs::remove_file(&self.path) {
                                Ok(()) => {}
                                Err(re) if re.kind() == io::ErrorKind::NotFound => {}
                                Err(re) => return Err(re),
                            }
                            match self.write_new_owned(&owner) {
                                Ok(()) => Ok(true),
                                Err(e2) if e2.kind() == io::ErrorKind::AlreadyExists => Ok(false),
                                Err(e2) => Err(e2),
                            }
                        }
                    }
                }
            }
            Err(e) => Err(e),
        }
    }

    /// Renew the lease, extending its expiry. Only succeeds if this handle owns
    /// the on-disk lease.
    pub fn renew(&mut self) -> io::Result<bool> {
        let owner = match &self.owner {
            Some(o) => o.clone(),
            None => return Ok(false),
        };
        match self.read_record()? {
            Some(rec) if rec.owner == owner => {
                let expires_ms = now_epoch_ms() + self.ttl_ms as u128;
                let renewed = LeaseRecord {
                    owner: owner.clone(),
                    expires_utc: format_utc(expires_ms),
                    expires_epoch_ms: expires_ms,
                };
                let payload = serde_json::to_vec(&renewed)
                    .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
                atomic_replace(&self.path, &payload)?;
                Ok(true)
            }
            _ => Ok(false),
        }
    }

    /// Release the lease if this handle owns it. Removes the file.
    pub fn release(&mut self) -> io::Result<bool> {
        let owner = match self.owner.take() {
            Some(o) => o,
            None => return Ok(false),
        };
        match self.read_record()? {
            Some(rec) if rec.owner == owner => {
                match fs::remove_file(&self.path) {
                    Ok(()) => Ok(true),
                    Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(true),
                    Err(e) => Err(e),
                }
            }
            _ => Ok(false),
        }
    }
}

/// Atomically replace `target` with `data`: write a unique temp sibling, fsync
/// it, rename over the target, then best-effort fsync the directory. Used by
/// lease renewal and by the main probe's atomic-replace assertion.
pub fn atomic_replace(target: &Path, data: &[u8]) -> io::Result<()> {
    let parent = target
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| PathBuf::from("."));
    fs::create_dir_all(&parent)?;

    let base = target
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| "target".to_string());

    // Unique temp name via a fresh UUID — never collides, no leftovers on success.
    let tmp_path = parent.join(format!(".{}.{}.tmp", base, Uuid::new_v4()));

    let mut f: File = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&tmp_path)?;
    let write_result = (|| {
        f.write_all(data)?;
        f.sync_all()
    })();
    if let Err(e) = write_result {
        let _ = fs::remove_file(&tmp_path);
        return Err(e);
    }
    drop(f);

    if let Err(e) = fs::rename(&tmp_path, target) {
        let _ = fs::remove_file(&tmp_path);
        return Err(e);
    }

    // Best-effort directory sync so the rename is durable (POSIX).
    #[cfg(unix)]
    {
        if let Ok(dir) = File::open(&parent) {
            let _ = dir.sync_all();
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(tag: &str) -> PathBuf {
        let base = std::env::temp_dir().join(format!(
            "kinglet-lease-test-{}-{}",
            tag,
            Uuid::new_v4()
        ));
        fs::create_dir_all(&base).unwrap();
        base
    }

    #[test]
    fn competitor_cannot_acquire_live_lease() {
        let dir = temp_dir("live");
        let path = dir.join("kinglet.lease");

        let mut holder = Lease::new(&path, 60_000); // long TTL — stays live
        assert!(holder.acquire().unwrap(), "holder should acquire");
        assert!(holder.owner().is_some());

        let mut competitor = Lease::new(&path, 60_000);
        assert!(
            !competitor.acquire().unwrap(),
            "competitor must be rejected while the lease is live"
        );
        assert!(
            competitor.owner().is_none(),
            "rejected competitor must not record ownership"
        );

        holder.release().unwrap();
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn expired_lease_can_be_replaced() {
        let dir = temp_dir("expired");
        let path = dir.join("kinglet.lease");

        let mut first = Lease::new(&path, 50); // 50ms TTL
        assert!(first.acquire().unwrap(), "first should acquire");

        std::thread::sleep(std::time::Duration::from_millis(250)); // outlive TTL

        let mut second = Lease::new(&path, 60_000);
        assert!(
            second.acquire().unwrap(),
            "expired lease must be stealable by a new owner"
        );
        assert_ne!(
            first.owner().unwrap(),
            second.owner().unwrap(),
            "stealer must have a distinct owner"
        );

        second.release().unwrap();
        let _ = fs::remove_dir_all(&dir);
    }
}
