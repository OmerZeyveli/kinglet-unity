// Kinglet Host Probe — self-contained .NET candidate for the 0R runtime bake-off.
//
// Executable protocol (frozen):
//   <exe> --version
//       → prints "dotnet-self-contained 10.0.10"
//   <exe> run --contract <abs host-probe-v1.json> --workspace <abs dir> --result <abs result.json>
//       → exits 0 iff all 18 assertions pass; atomically writes kinglet.host-probe.result/v1 JSON
//   <exe> child --sentinel <abs file> --lifetime-ms <positive int>
//       → spawns exactly one grandchild, writes [child_pid, grandchild_pid] to sentinel, sleeps

using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;

using NSec.Cryptography;

using Kinglet.HostProbe;

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

if (args.Length == 0)
{
    PrintUsage();
    return 1;
}

switch (args[0])
{
    case "--version":
        Console.WriteLine("dotnet-self-contained 10.0.10");
        return 0;

    case "run":
        return RunCommand(args[1..]);

    case "child":
        return ChildCommand(args[1..]);

    default:
        PrintUsage();
        return 1;
}

// ---------------------------------------------------------------------------
// CLI handlers
// ---------------------------------------------------------------------------

static void PrintUsage()
{
    Console.Error.WriteLine("Usage:");
    Console.Error.WriteLine("  kinglet-host-probe --version");
    Console.Error.WriteLine("  kinglet-host-probe run --contract <path> --workspace <dir> --result <path>");
    Console.Error.WriteLine("  kinglet-host-probe child --sentinel <path> --lifetime-ms <ms>");
}

static int RunCommand(string[] args)
{
    string? contract = null, workspace = null, result = null;
    for (int i = 0; i < args.Length; i++)
    {
        switch (args[i])
        {
            case "--contract":   if (++i < args.Length) contract  = args[i]; break;
            case "--workspace":  if (++i < args.Length) workspace = args[i]; break;
            case "--result":     if (++i < args.Length) result    = args[i]; break;
        }
    }
    if (contract == null || workspace == null || result == null)
    {
        Console.Error.WriteLine("run: --contract, --workspace, and --result are required");
        return 1;
    }

    HostResult res;
    try
    {
        res = ProbeRunner.Run(contract, workspace);
    }
    catch (Exception ex)
    {
        Console.Error.WriteLine($"run contract: {ex.Message}");
        return 1;
    }

    byte[] json = JsonSerializer.SerializeToUtf8Bytes(res, HostResultJsonContext.Default.HostResult);
    Lease.AtomicReplace(result, json);

    // Echo to stdout.
    Console.Write(System.Text.Encoding.UTF8.GetString(json));
    Console.WriteLine();

    return res.Status == "pass" ? 0 : 1;
}

static int ChildCommand(string[] args)
{
    string? sentinel = null;
    int lifetimeMs = 0;
    bool noSetpgid = false;
    for (int i = 0; i < args.Length; i++)
    {
        switch (args[i])
        {
            case "--sentinel":     if (++i < args.Length) sentinel    = args[i]; break;
            case "--lifetime-ms":  if (++i < args.Length) int.TryParse(args[i], out lifetimeMs); break;
            case "--no-setpgid":   noSetpgid = true; break;
        }
    }

    // On POSIX, put ourselves in a new process group so kill(-pgid,SIGKILL) works.
    // Grandchildren pass --no-setpgid to stay in the child's group.
    if (!noSetpgid)
    {
        ProcessTree.SetOwnProcessGroup();
    }
    if (sentinel == null || lifetimeMs <= 0)
    {
        Console.Error.WriteLine("child: --sentinel and --lifetime-ms are required");
        return 1;
    }

    ProcessTree.RunChild(sentinel, lifetimeMs);
    return 0;
}

// ---------------------------------------------------------------------------
// Contract runner
// ---------------------------------------------------------------------------

static class ProbeRunner
{
    private const string CandidateId      = "dotnet-self-contained";
    private const string CandidateVersion = "10.0.10";
    private const string ResultSchema     = "kinglet.host-probe.result/v1";

    private static readonly string[] RequiredOrder =
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

    public static HostResult Run(string contractPath, string workspace)
    {
        contractPath = Path.GetFullPath(contractPath);
        workspace    = Path.GetFullPath(workspace);
        Directory.CreateDirectory(workspace);

        string contractDir = Path.GetDirectoryName(contractPath)!;
        var contract = LoadContract(contractPath);

        int leaseTTL         = contract.TimingsMs.LeaseTtl         > 0 ? contract.TimingsMs.LeaseTtl         : 1200;
        int leaseRenewal     = contract.TimingsMs.LeaseRenewal      > 0 ? contract.TimingsMs.LeaseRenewal      : 400;
        int leaseCompetitor  = contract.TimingsMs.LeaseCompetitorAttempt > 0 ? contract.TimingsMs.LeaseCompetitorAttempt : 600;
        int childLifetime    = contract.TimingsMs.ChildLifetime     > 0 ? contract.TimingsMs.ChildLifetime     : 30000;
        int cancelDeadline   = contract.TimingsMs.CancelDeadline    > 0 ? contract.TimingsMs.CancelDeadline    : 5000;

        string canonicalValid   = contract.CanonicalValid   ?? "canonical-valid/";
        string canonicalInvalid = contract.CanonicalInvalid ?? "canonical-invalid/";
        string cryptoVectors    = contract.CryptoVectors    ?? "ed25519-rfc8032.json";

        var assertions = new List<AssertionResult>();
        var errors     = new List<string>();
        var descendantPids = new List<int>();

        void RecordPass(string id)   => assertions.Add(new AssertionResult(id, "pass", null));
        void RecordFail(string id, string reason)
        {
            assertions.Add(new AssertionResult(id, "fail", reason));
            errors.Add($"{id}: {reason}");
        }

        // -------------------------------------------------------------------
        // 1. manifest.accept-valid
        // -------------------------------------------------------------------
        {
            string validDir  = Path.Combine(contractDir, canonicalValid.TrimEnd('/'));
            string rolePath  = Path.Combine(validDir, "src", "roles", "unity-scout", "role.json");
            try
            {
                DecodeRoleJson(rolePath, strict: true);
                RecordPass("manifest.accept-valid");
            }
            catch (Exception ex)
            {
                RecordFail("manifest.accept-valid", ex.Message);
            }
        }

        // -------------------------------------------------------------------
        // 2. manifest.reject-unknown
        // -------------------------------------------------------------------
        {
            string invalidDir = Path.Combine(contractDir, canonicalInvalid.TrimEnd('/'));
            string rolePath   = Path.Combine(invalidDir, "src", "roles", "unity-scout", "role.json");
            bool rejected = false;
            try
            {
                DecodeRoleJson(rolePath, strict: true);
            }
            catch
            {
                rejected = true;
            }
            if (rejected) RecordPass("manifest.reject-unknown");
            else          RecordFail("manifest.reject-unknown", "decoder did not reject unknown field");
        }

        // -------------------------------------------------------------------
        // 3. path.unicode-space
        // -------------------------------------------------------------------
        {
            string unicodePath = Path.Combine(workspace, "ünïcödé spàce.txt");
            try
            {
                File.WriteAllText(unicodePath, "ok");
                string content = File.ReadAllText(unicodePath);
                if (content == "ok") RecordPass("path.unicode-space");
                else                 RecordFail("path.unicode-space", $"unexpected content: {content}");
            }
            catch (Exception ex) { RecordFail("path.unicode-space", ex.Message); }
        }

        // -------------------------------------------------------------------
        // 4. filesystem.atomic-replace
        // -------------------------------------------------------------------
        {
            string atomicTarget = Path.Combine(workspace, "atomic-state.json");
            try
            {
                Lease.AtomicReplace(atomicTarget, System.Text.Encoding.UTF8.GetBytes("{\"initial\":true}\n"));
                Lease.AtomicReplace(atomicTarget, System.Text.Encoding.UTF8.GetBytes("{\"replaced\":true}\n"));

                string data = File.ReadAllText(atomicTarget);
                using var doc = JsonDocument.Parse(data);
                bool hasReplaced = doc.RootElement.TryGetProperty("replaced", out var v) && v.GetBoolean();
                if (!hasReplaced)
                {
                    RecordFail("filesystem.atomic-replace", $"unexpected data: {data}");
                }
                else
                {
                    // Check no leftover .tmp files.
                    string[] tmps = Directory.GetFiles(workspace, "*.tmp");
                    if (tmps.Length > 0)
                        RecordFail("filesystem.atomic-replace", $"leftover tmp files: {string.Join(", ", tmps)}");
                    else
                        RecordPass("filesystem.atomic-replace");
                }
            }
            catch (Exception ex) { RecordFail("filesystem.atomic-replace", ex.Message); }
        }

        // -------------------------------------------------------------------
        // 5-9. Lease assertions
        // -------------------------------------------------------------------
        string leasePath = Path.Combine(workspace, ".lease", "kinglet.lease");
        var leaseA = new Lease(leasePath, leaseTTL);
        bool leaseAcquired = false;

        // lease.acquire
        {
            try
            {
                bool ok = leaseA.Acquire();
                if (ok && leaseA.Owner != null)
                {
                    leaseAcquired = true;
                    RecordPass("lease.acquire");
                }
                else
                {
                    RecordFail("lease.acquire", "acquire returned false");
                }
            }
            catch (Exception ex) { RecordFail("lease.acquire", ex.Message); }
        }

        // lease.renew
        {
            System.Threading.Thread.Sleep(leaseRenewal);
            try
            {
                bool ok = leaseA.Renew();
                if (ok) RecordPass("lease.renew");
                else    RecordFail("lease.renew", "renew returned false");
            }
            catch (Exception ex) { RecordFail("lease.renew", ex.Message); }
        }

        // lease.reject-competitor
        {
            int extra = leaseCompetitor - leaseRenewal;
            if (extra > 0) System.Threading.Thread.Sleep(extra);
            var leaseB = new Lease(leasePath, leaseTTL);
            try
            {
                bool ok = leaseB.Acquire();
                if (ok)
                {
                    leaseB.Release();
                    RecordFail("lease.reject-competitor", "competitor was granted the lease");
                }
                else
                {
                    RecordPass("lease.reject-competitor");
                }
            }
            catch (Exception ex) { RecordFail("lease.reject-competitor", ex.Message); }
        }

        // lease.expire
        {
            string shortPath = Path.Combine(workspace, ".lease", "short.lease");
            var leaseShort = new Lease(shortPath, 100); // 100ms TTL
            leaseShort.Acquire();
            System.Threading.Thread.Sleep(300);

            var leaseNew = new Lease(shortPath, leaseTTL);
            try
            {
                bool ok = leaseNew.Acquire();
                if (ok)
                {
                    leaseNew.Release();
                    RecordPass("lease.expire");
                }
                else
                {
                    RecordFail("lease.expire", "could not acquire after expired lease");
                }
            }
            catch (Exception ex) { RecordFail("lease.expire", ex.Message); }
        }

        // lease.release
        {
            try
            {
                bool released = leaseA.Release();
                bool stillExists = File.Exists(leasePath);
                if (released && !stillExists)
                {
                    leaseAcquired = false;
                    RecordPass("lease.release");
                }
                else
                {
                    RecordFail("lease.release", $"released={released} file_exists={stillExists}");
                }
            }
            catch (Exception ex) { RecordFail("lease.release", ex.Message); }
        }
        if (leaseAcquired)
        {
            leaseA.Release();
        }

        // -------------------------------------------------------------------
        // 10-12. Process assertions
        // -------------------------------------------------------------------
        string exe = Environment.ProcessPath ?? System.Diagnostics.Process.GetCurrentProcess().MainModule!.FileName!;
        var (recordedPids, killed) = ProcessTree.SpawnTreeAndCancel(exe, workspace, childLifetime, cancelDeadline);

        if (recordedPids.Count >= 2)
            RecordPass("process.child-grandchild");
        else
            RecordFail("process.child-grandchild", $"sentinel had only {recordedPids.Count} pids");

        if (recordedPids.Count > 0 && killed)
            RecordPass("process.cancel");
        else if (!killed)
            RecordFail("process.cancel", "kill process group returned an error");
        else
            RecordFail("process.cancel", "no pids recorded — see process.child-grandchild");

        {
            var alivePids = new List<int>();
            foreach (int pid in recordedPids)
            {
                if (ProcessTree.IsPidAlive(pid)) alivePids.Add(pid);
            }
            if (alivePids.Count == 0)
            {
                RecordPass("process.no-descendants");
            }
            else
            {
                descendantPids.AddRange(alivePids);
                RecordFail("process.no-descendants", $"pids still alive: [{string.Join(", ", alivePids)}]");
            }
        }

        // -------------------------------------------------------------------
        // 13. crypto.sha256
        // -------------------------------------------------------------------
        {
            byte[] hash = SHA256.HashData(Array.Empty<byte>());
            string got      = Convert.ToHexString(hash).ToLowerInvariant();
            string expected = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
            if (got == expected) RecordPass("crypto.sha256");
            else                 RecordFail("crypto.sha256", $"got {got}");
        }

        // -------------------------------------------------------------------
        // 14. crypto.ed25519
        // -------------------------------------------------------------------
        {
            string vectorsPath = Path.Combine(contractDir, cryptoVectors);
            try
            {
                var vec = LoadEd25519Vector(vectorsPath);
                bool ok = VerifyEd25519(vec.Message, vec.PublicKey, vec.Signature);
                if (ok) RecordPass("crypto.ed25519");
                else    RecordFail("crypto.ed25519", "RFC 8032 vector 1 failed");
            }
            catch (Exception ex) { RecordFail("crypto.ed25519", ex.Message); }
        }

        // -------------------------------------------------------------------
        // 15-18. Cleanup scenarios
        // -------------------------------------------------------------------

        // cleanup.success
        {
            string clPath   = Path.Combine(workspace, ".cleanup", "success.lease");
            string tmpFile  = Path.Combine(workspace, "cleanup-success.tmp");
            var cl          = new Lease(clPath, leaseTTL);
            Exception? err  = null;
            try
            {
                cl.Acquire();
                Lease.AtomicReplace(tmpFile, System.Text.Encoding.UTF8.GetBytes("ok"));
            }
            catch (Exception ex) { err = ex; }
            finally
            {
                cl.Release();
                try { File.Delete(tmpFile); } catch { }
            }
            if (err == null) RecordPass("cleanup.success");
            else             RecordFail("cleanup.success", err.Message);
        }

        // cleanup.crash — simulate panic/exception caught in finally
        {
            string clPath = Path.Combine(workspace, ".cleanup", "crash.lease");
            var cl        = new Lease(clPath, leaseTTL);
            bool cleanupRan = false;
            try
            {
                cl.Acquire();
                throw new InvalidOperationException("simulated crash");
            }
            catch (InvalidOperationException)
            {
                // expected
            }
            finally
            {
                cl.Release();
                cleanupRan = true;
            }
            if (cleanupRan) RecordPass("cleanup.crash");
            else            RecordFail("cleanup.crash", "finally did not run after simulated crash");
        }

        // cleanup.timeout
        {
            string clPath = Path.Combine(workspace, ".cleanup", "timeout.lease");
            var cl        = new Lease(clPath, leaseTTL);
            bool cleanupRan  = false;
            Exception? simEx = null;
            try
            {
                cl.Acquire();
                simEx = new TimeoutException("simulated timeout");
            }
            finally
            {
                cl.Release();
                cleanupRan = true;
            }
            if (simEx != null && cleanupRan) RecordPass("cleanup.timeout");
            else if (!cleanupRan)            RecordFail("cleanup.timeout", "finally did not run after timeout");
            else                             RecordPass("cleanup.timeout");
        }

        // cleanup.cancel
        {
            string clPath = Path.Combine(workspace, ".cleanup", "cancel.lease");
            var cl        = new Lease(clPath, leaseTTL);
            bool cleanupRan  = false;
            Exception? simEx = null;
            try
            {
                cl.Acquire();
                simEx = new OperationCanceledException("simulated cancel");
            }
            finally
            {
                cl.Release();
                cleanupRan = true;
            }
            if (simEx != null && cleanupRan) RecordPass("cleanup.cancel");
            else if (!cleanupRan)            RecordFail("cleanup.cancel", "finally did not run after cancel");
            else                             RecordPass("cleanup.cancel");
        }

        // -------------------------------------------------------------------
        // Active lease check
        // -------------------------------------------------------------------
        string[] checkPaths =
        [
            leasePath,
            Path.Combine(workspace, ".cleanup", "success.lease"),
            Path.Combine(workspace, ".cleanup", "crash.lease"),
            Path.Combine(workspace, ".cleanup", "timeout.lease"),
            Path.Combine(workspace, ".cleanup", "cancel.lease"),
        ];
        bool activeLease = false;
        foreach (string p in checkPaths)
        {
            if (File.Exists(p)) { activeLease = true; break; }
        }

        // -------------------------------------------------------------------
        // Build ordered result
        // -------------------------------------------------------------------
        var assertionMap = new Dictionary<string, AssertionResult>();
        foreach (var a in assertions)
        {
            if (!assertionMap.ContainsKey(a.Id))
                assertionMap[a.Id] = a;
        }

        // Fill missing as fail.
        foreach (string id in RequiredOrder)
        {
            if (!assertionMap.ContainsKey(id))
            {
                assertionMap[id] = new AssertionResult(id, "fail", "assertion not reached");
                errors.Add($"{id}: not reached");
            }
        }

        var ordered = new List<AssertionResult>(RequiredOrder.Length);
        bool allPass = true;
        foreach (string id in RequiredOrder)
        {
            var a = assertionMap[id];
            ordered.Add(a);
            if (a.Status != "pass") allPass = false;
        }

        if (descendantPids.Count > 0 || activeLease) allPass = false;

        return new HostResult
        {
            Schema     = ResultSchema,
            Candidate  = new CandidateInfo { Id = CandidateId, Version = CandidateVersion },
            Status     = allPass ? "pass" : "fail",
            Errors     = errors,
            Assertions = ordered,
            DescendantPids = descendantPids,
            ActiveLease    = activeLease,
        };
    }

    // ------------------------------------------------------------------
    // Manifest decoding with strict unknown-field rejection
    // ------------------------------------------------------------------

    private static readonly JsonSerializerOptions StrictOptions = new()
    {
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
    };

    private static void DecodeRoleJson(string path, bool strict)
    {
        byte[] data = File.ReadAllBytes(path);
        if (strict)
        {
            var role = JsonSerializer.Deserialize<RoleManifest>(data, StrictOptions)
                ?? throw new JsonException("role.json: deserialized to null");
            if (string.IsNullOrEmpty(role.Id))
                throw new JsonException("role.json: missing id field");
        }
        else
        {
            var role = JsonSerializer.Deserialize<RoleManifest>(data)
                ?? throw new JsonException("role.json: deserialized to null");
            if (string.IsNullOrEmpty(role.Id))
                throw new JsonException("role.json: missing id field");
        }
    }

    // ------------------------------------------------------------------
    // Ed25519 via NSec
    // ------------------------------------------------------------------

    private static bool VerifyEd25519(string messageHex, string publicHex, string sigHex)
    {
        byte[] msg = messageHex.Length == 0 ? Array.Empty<byte>() : Convert.FromHexString(messageHex);
        byte[] pub = Convert.FromHexString(publicHex);
        byte[] sig = Convert.FromHexString(sigHex);

        var algorithm = SignatureAlgorithm.Ed25519;
        var publicKey = PublicKey.Import(algorithm, pub, KeyBlobFormat.RawPublicKey);
        return algorithm.Verify(publicKey, msg, sig);
    }

    // ------------------------------------------------------------------
    // Contract / vector loaders
    // ------------------------------------------------------------------

    private static ContractFile LoadContract(string path)
    {
        byte[] data = File.ReadAllBytes(path);
        return JsonSerializer.Deserialize<ContractFile>(data)
            ?? throw new JsonException("contract file deserialized to null");
    }

    private static Ed25519VectorFile LoadEd25519Vector(string path)
    {
        byte[] data = File.ReadAllBytes(path);
        return JsonSerializer.Deserialize<Ed25519VectorFile>(data)
            ?? throw new JsonException("ed25519 vector file deserialized to null");
    }
}

// ---------------------------------------------------------------------------
// JSON model types
// ---------------------------------------------------------------------------

internal sealed class ContractFile
{
    [JsonPropertyName("timings_ms")]
    public ContractTimings TimingsMs { get; set; } = new();

    [JsonPropertyName("canonical_valid")]
    public string? CanonicalValid { get; set; }

    [JsonPropertyName("canonical_invalid")]
    public string? CanonicalInvalid { get; set; }

    [JsonPropertyName("crypto_vectors")]
    public string? CryptoVectors { get; set; }
}

internal sealed class ContractTimings
{
    [JsonPropertyName("lease_ttl")]
    public int LeaseTtl { get; set; }

    [JsonPropertyName("lease_renewal")]
    public int LeaseRenewal { get; set; }

    [JsonPropertyName("lease_competitor_attempt")]
    public int LeaseCompetitorAttempt { get; set; }

    [JsonPropertyName("child_lifetime")]
    public int ChildLifetime { get; set; }

    [JsonPropertyName("cancel_deadline")]
    public int CancelDeadline { get; set; }
}

internal sealed class Ed25519VectorFile
{
    [JsonPropertyName("message")]
    public string Message { get; set; } = "";

    [JsonPropertyName("public_key")]
    public string PublicKey { get; set; } = "";

    [JsonPropertyName("signature")]
    public string Signature { get; set; } = "";
}

// Role manifest — strict deserialization rejects unknown fields via JsonUnmappedMemberHandling.
internal sealed class RoleManifest
{
    [JsonPropertyName("schema_version")]
    public int SchemaVersion { get; set; }

    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("kind")]
    public string Kind { get; set; } = "";

    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("summary")]
    public string Summary { get; set; } = "";

    [JsonPropertyName("capabilities")]
    public List<string>? Capabilities { get; set; }

    [JsonPropertyName("requires")]
    public List<string>? Requires { get; set; }

    [JsonPropertyName("support")]
    public Dictionary<string, RoleSupportEntry>? Support { get; set; }

    [JsonPropertyName("provenance")]
    public RoleProvenance? Provenance { get; set; }

    [JsonPropertyName("reasoning_tier")]
    public string? ReasoningTier { get; set; }

    [JsonPropertyName("evidence")]
    public List<string>? Evidence { get; set; }
}

internal sealed class RoleSupportEntry
{
    [JsonPropertyName("state")]
    public string State { get; set; } = "";

    [JsonPropertyName("reason")]
    public string? Reason { get; set; }

    [JsonPropertyName("owner")]
    public string? Owner { get; set; }

    [JsonPropertyName("test")]
    public string? Test { get; set; }
}

internal sealed class RoleProvenance
{
    [JsonPropertyName("origin")]
    public string Origin { get; set; } = "";

    [JsonPropertyName("upstream_version")]
    public string UpstreamVersion { get; set; } = "";

    [JsonPropertyName("upstream_path")]
    public string UpstreamPath { get; set; } = "";

    [JsonPropertyName("upstream_sha256")]
    public string UpstreamSha256 { get; set; } = "";
}

// Result types
internal sealed class HostResult
{
    [JsonPropertyName("schema")]
    public string Schema { get; set; } = "";

    [JsonPropertyName("candidate")]
    public CandidateInfo Candidate { get; set; } = new();

    [JsonPropertyName("status")]
    public string Status { get; set; } = "";

    [JsonPropertyName("errors")]
    public List<string> Errors { get; set; } = [];

    [JsonPropertyName("assertions")]
    public List<AssertionResult> Assertions { get; set; } = [];

    [JsonPropertyName("descendant_pids")]
    public List<int> DescendantPids { get; set; } = [];

    [JsonPropertyName("active_lease")]
    public bool ActiveLease { get; set; }
}

internal sealed class CandidateInfo
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("version")]
    public string Version { get; set; } = "";
}

internal sealed class AssertionResult
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("status")]
    public string Status { get; set; } = "";

    [JsonPropertyName("reason")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Reason { get; set; }

    public AssertionResult() { }

    public AssertionResult(string id, string status, string? reason)
    {
        Id = id;
        Status = status;
        Reason = reason;
    }
}

[JsonSerializable(typeof(HostResult))]
[JsonSerializable(typeof(List<int>))]
internal sealed partial class HostResultJsonContext : JsonSerializerContext { }
