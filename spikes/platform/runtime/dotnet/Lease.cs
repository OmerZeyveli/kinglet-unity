using System;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Kinglet.HostProbe;

/// <summary>
/// File-backed exclusive advisory lease.
/// The file stores {"owner":"<hex>","expires_utc":"<ISO8601>"}.
/// </summary>
internal sealed class Lease
{
    private readonly string _path;
    private readonly int _ttlMs;
    private string? _owner; // non-null when this instance holds the lease

    public Lease(string path, int ttlMs)
    {
        _path = path;
        _ttlMs = ttlMs;
    }

    public string? Owner => _owner;

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------

    /// <summary>Tries to acquire the lease. Returns true on success, false if busy.</summary>
    public bool Acquire()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);

        string owner = GenerateOwner();
        var record = new LeaseRecord(owner, Expiry());
        byte[] payload = Serialize(record);

        // O_CREATE | O_EXCL — atomic exclusive create.
        FileStream? fs = TryCreateExclusive(_path);
        if (fs != null)
        {
            using (fs)
            {
                fs.Write(payload);
                fs.Flush(flushToDisk: true);
            }
            _owner = owner;
            return true;
        }

        // File exists — check expiry.
        LeaseRecord? existing = TryReadRecord(_path);
        if (existing == null)
        {
            // Unreadable or gone — treat as busy.
            return false;
        }
        if (!IsExpired(existing))
        {
            return false; // actively held
        }

        // Expired — steal it.
        try { File.Delete(_path); } catch (FileNotFoundException) { }
        catch { return false; }

        return Acquire(); // retry
    }

    /// <summary>Refreshes the lease expiry. Only succeeds if this instance owns it.</summary>
    public bool Renew()
    {
        if (_owner == null) return false;
        LeaseRecord? rec = TryReadRecord(_path);
        if (rec == null || rec.Owner != _owner) return false;

        var updated = new LeaseRecord(_owner, Expiry());
        AtomicReplace(_path, Serialize(updated));
        return true;
    }

    /// <summary>Removes the lease file if this instance owns it.</summary>
    public bool Release()
    {
        if (_owner == null) return false;
        LeaseRecord? rec = TryReadRecord(_path);
        if (rec != null && rec.Owner == _owner)
        {
            try
            {
                File.Delete(_path);
                _owner = null;
                return true;
            }
            catch (FileNotFoundException)
            {
                _owner = null;
                return true;
            }
            catch
            {
                _owner = null;
                return false;
            }
        }
        _owner = null;
        return false;
    }

    /// <summary>Returns true if the lease file exists (regardless of owner).</summary>
    public bool IsActive() => File.Exists(_path);

    // ------------------------------------------------------------------
    // Internal helpers
    // ------------------------------------------------------------------

    private DateTime Expiry() => DateTime.UtcNow.AddMilliseconds(_ttlMs);

    private static bool IsExpired(LeaseRecord rec)
    {
        return DateTime.UtcNow > rec.ExpiresUtc;
    }

    private static string GenerateOwner()
    {
        Span<byte> bytes = stackalloc byte[16];
        RandomNumberGenerator.Fill(bytes);
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }

    private static byte[] Serialize(LeaseRecord record)
    {
        return JsonSerializer.SerializeToUtf8Bytes(record, LeaseJsonContext.Default.LeaseRecord);
    }

    private static LeaseRecord? TryReadRecord(string path)
    {
        try
        {
            byte[] data = File.ReadAllBytes(path);
            var rec = JsonSerializer.Deserialize(data, LeaseJsonContext.Default.LeaseRecord);
            if (rec == null || rec.Owner.Length == 0) return null;
            return rec;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Opens path exclusively with FileMode.CreateNew. Returns null if it already exists.
    /// </summary>
    private static FileStream? TryCreateExclusive(string path)
    {
        try
        {
            return new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        }
        catch (IOException)
        {
            return null;
        }
    }

    // ------------------------------------------------------------------
    // Atomic replace (used by Renew)
    // ------------------------------------------------------------------

    internal static void AtomicReplace(string target, byte[] data)
    {
        string dir = Path.GetDirectoryName(target)!;
        Directory.CreateDirectory(dir);
        string tmp = target + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var fs = new FileStream(tmp, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                fs.Write(data);
                fs.Flush(flushToDisk: true);
            }
            File.Move(tmp, target, overwrite: true);
        }
        catch
        {
            try { File.Delete(tmp); } catch { }
            throw;
        }
    }
}

// ------------------------------------------------------------------
// JSON model for lease file
// ------------------------------------------------------------------

internal sealed class LeaseRecord
{
    [JsonPropertyName("owner")]
    public string Owner { get; set; } = "";

    [JsonPropertyName("expires_utc")]
    public DateTime ExpiresUtc { get; set; }

    public LeaseRecord() { }

    public LeaseRecord(string owner, DateTime expiresUtc)
    {
        Owner = owner;
        ExpiresUtc = expiresUtc;
    }
}

[JsonSerializable(typeof(LeaseRecord))]
internal sealed partial class LeaseJsonContext : JsonSerializerContext { }
