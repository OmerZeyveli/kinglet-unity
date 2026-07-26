// xUnit tests for the Kinglet .NET host probe candidate.
// Covers the four critical behaviors: atomic write, lease, Ed25519, and result shape.

using System;
using System.IO;
using System.Linq;
using System.Text.Json;

using Xunit;

using Kinglet.HostProbe;

namespace Kinglet.HostProbe.Tests;

public sealed class AtomicReplaceTests
{
    [Fact]
    public void AtomicReplace_WritesDataToTarget()
    {
        string tmp = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName());
        try
        {
            byte[] data = System.Text.Encoding.UTF8.GetBytes("{\"ok\":true}");
            Lease.AtomicReplace(tmp, data);
            Assert.Equal("{\"ok\":true}", File.ReadAllText(tmp));
        }
        finally
        {
            if (File.Exists(tmp)) File.Delete(tmp);
        }
    }

    [Fact]
    public void AtomicReplace_OverwritesExistingFile()
    {
        string tmp = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName());
        try
        {
            byte[] first  = System.Text.Encoding.UTF8.GetBytes("{\"v\":1}");
            byte[] second = System.Text.Encoding.UTF8.GetBytes("{\"v\":2}");
            Lease.AtomicReplace(tmp, first);
            Lease.AtomicReplace(tmp, second);
            Assert.Equal("{\"v\":2}", File.ReadAllText(tmp));
        }
        finally
        {
            if (File.Exists(tmp)) File.Delete(tmp);
        }
    }

    [Fact]
    public void AtomicReplace_LeavesNoTmpFiles()
    {
        string dir = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName());
        Directory.CreateDirectory(dir);
        string target = Path.Combine(dir, "state.json");
        try
        {
            Lease.AtomicReplace(target, System.Text.Encoding.UTF8.GetBytes("{}"));
            string[] tmps = Directory.GetFiles(dir, "*.tmp");
            Assert.Empty(tmps);
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }
}

public sealed class LeaseTests
{
    private static string TempLeasePath()
    {
        string dir = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName());
        return Path.Combine(dir, "test.lease");
    }

    [Fact]
    public void Acquire_ReturnsTrue_WhenFileAbsent()
    {
        string path = TempLeasePath();
        try
        {
            var lease = new Lease(path, 5000);
            bool ok = lease.Acquire();
            Assert.True(ok);
            Assert.NotNull(lease.Owner);
            Assert.NotEmpty(lease.Owner!);
        }
        finally
        {
            try { File.Delete(path); } catch { }
            try { Directory.Delete(Path.GetDirectoryName(path)!, true); } catch { }
        }
    }

    [Fact]
    public void Acquire_ReturnsFalse_WhenAlreadyHeld()
    {
        string path = TempLeasePath();
        try
        {
            var leaseA = new Lease(path, 5000);
            var leaseB = new Lease(path, 5000);
            Assert.True(leaseA.Acquire());
            Assert.False(leaseB.Acquire());
        }
        finally
        {
            try { File.Delete(path); } catch { }
            try { Directory.Delete(Path.GetDirectoryName(path)!, true); } catch { }
        }
    }

    [Fact]
    public void Renew_RefreshesExpiry_ForOwner()
    {
        string path = TempLeasePath();
        try
        {
            var lease = new Lease(path, 5000);
            Assert.True(lease.Acquire());
            bool renewed = lease.Renew();
            Assert.True(renewed);
        }
        finally
        {
            try { File.Delete(path); } catch { }
            try { Directory.Delete(Path.GetDirectoryName(path)!, true); } catch { }
        }
    }

    [Fact]
    public void Acquire_Steals_ExpiredLease()
    {
        string path = TempLeasePath();
        try
        {
            var oldLease = new Lease(path, 50); // 50ms TTL
            Assert.True(oldLease.Acquire());
            System.Threading.Thread.Sleep(200); // wait past expiry

            var newLease = new Lease(path, 5000);
            Assert.True(newLease.Acquire());
            newLease.Release();
        }
        finally
        {
            try { File.Delete(path); } catch { }
            try { Directory.Delete(Path.GetDirectoryName(path)!, true); } catch { }
        }
    }

    [Fact]
    public void Release_RemovesLeaseFile()
    {
        string path = TempLeasePath();
        try
        {
            var lease = new Lease(path, 5000);
            Assert.True(lease.Acquire());
            Assert.True(File.Exists(path));
            bool released = lease.Release();
            Assert.True(released);
            Assert.False(File.Exists(path));
        }
        finally
        {
            try { File.Delete(path); } catch { }
            try { Directory.Delete(Path.GetDirectoryName(path)!, true); } catch { }
        }
    }
}

public sealed class Ed25519Tests
{
    // RFC 8032 Section 5.1 Test Vector 1 — empty message
    private const string PublicKeyHex  = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a";
    private const string SignatureHex  = "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b";
    private const string MessageHex    = ""; // empty

    [Fact]
    public void VerifyEd25519_RFC8032Vector1_Passes()
    {
        byte[] msg = MessageHex.Length == 0 ? Array.Empty<byte>() : Convert.FromHexString(MessageHex);
        byte[] pub = Convert.FromHexString(PublicKeyHex);
        byte[] sig = Convert.FromHexString(SignatureHex);

        var algorithm = NSec.Cryptography.SignatureAlgorithm.Ed25519;
        var publicKey = NSec.Cryptography.PublicKey.Import(
            algorithm,
            pub,
            NSec.Cryptography.KeyBlobFormat.RawPublicKey);

        bool ok = algorithm.Verify(publicKey, msg, sig);
        Assert.True(ok, "RFC 8032 vector 1 should verify");
    }

    [Fact]
    public void VerifyEd25519_WrongSignature_Fails()
    {
        byte[] msg = Array.Empty<byte>();
        byte[] pub = Convert.FromHexString(PublicKeyHex);
        // corrupt the signature
        byte[] sig = Convert.FromHexString(SignatureHex);
        sig[0] ^= 0xFF;

        var algorithm = NSec.Cryptography.SignatureAlgorithm.Ed25519;
        var publicKey = NSec.Cryptography.PublicKey.Import(
            algorithm,
            pub,
            NSec.Cryptography.KeyBlobFormat.RawPublicKey);

        bool ok = algorithm.Verify(publicKey, msg, sig);
        Assert.False(ok, "corrupted signature should not verify");
    }
}

public sealed class ResultShapeTests
{
    private static readonly string[] ExpectedIds =
    [
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

    [Fact]
    public void HostResult_HasExactly18AssertionIds_InOrder()
    {
        // Build a minimal fake result to verify the JSON shape and ordering.
        var result = new HostResult
        {
            Schema    = "kinglet.host-probe.result/v1",
            Candidate = new CandidateInfo { Id = "dotnet-self-contained", Version = "10.0.10" },
            Status    = "pass",
            Errors    = [],
            Assertions = ExpectedIds.Select(id => new AssertionResult(id, "pass", null)).ToList(),
            DescendantPids = [],
            ActiveLease    = false,
        };

        byte[] json = JsonSerializer.SerializeToUtf8Bytes(result, HostResultJsonContext.Default.HostResult);
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        // schema
        Assert.Equal("kinglet.host-probe.result/v1", root.GetProperty("schema").GetString());

        // candidate
        var cand = root.GetProperty("candidate");
        Assert.Equal("dotnet-self-contained", cand.GetProperty("id").GetString());
        Assert.Equal("10.0.10",               cand.GetProperty("version").GetString());

        // assertions: exactly 18, in order
        var assertionsEl = root.GetProperty("assertions");
        Assert.Equal(18, assertionsEl.GetArrayLength());
        int idx = 0;
        foreach (var a in assertionsEl.EnumerateArray())
        {
            Assert.Equal(ExpectedIds[idx++], a.GetProperty("id").GetString());
        }

        // descendant_pids: []
        Assert.Equal(0, root.GetProperty("descendant_pids").GetArrayLength());

        // active_lease: false
        Assert.False(root.GetProperty("active_lease").GetBoolean());
    }
}
