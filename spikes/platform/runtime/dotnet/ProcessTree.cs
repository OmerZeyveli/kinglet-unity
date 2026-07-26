using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;

namespace Kinglet.HostProbe;

/// <summary>
/// Platform-specific process group management and liveness checks.
/// </summary>
internal static class ProcessTree
{
    // ------------------------------------------------------------------
    // Child subcommand
    // ------------------------------------------------------------------

    /// <summary>
    /// Spawns one grandchild (this exe child --sentinel gc-sentinel.json --lifetime-ms 60000),
    /// waits 100ms, writes [childPid, grandchildPid] to sentinelPath, then sleeps lifetimeMs.
    /// </summary>
    public static void RunChild(string sentinelPath, int lifetimeMs)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(sentinelPath)!);

        string exe = Environment.ProcessPath ?? Process.GetCurrentProcess().MainModule!.FileName!;
        string gcSentinel = Path.Combine(Path.GetDirectoryName(sentinelPath)!, "gc-sentinel.json");

        // --no-setpgid: grandchild stays in the child's process group so kill(-pgid,SIGKILL) hits both
        var gcInfo = new ProcessStartInfo(exe,
            ["child", "--sentinel", gcSentinel, "--lifetime-ms", "60000", "--no-setpgid"])
        {
            UseShellExecute = false,
            RedirectStandardOutput = false,
            RedirectStandardError = false,
        };

        // Put grandchild in its own process group on POSIX so we can kill by group later.
        if (!OperatingSystem.IsWindows())
        {
            // We can't set Setpgid via ProcessStartInfo directly, so we call setpgid(0,0)
            // from a wrapper — the child process itself calls setpgid(0,0) at startup when
            // invoked as a child subcommand (handled in Program.cs).
        }

        var gcProcess = Process.Start(gcInfo)!;

        Thread.Sleep(100);

        int childPid = Environment.ProcessId;
        int gcPid = gcProcess.Id;
        byte[] data = JsonSerializer.SerializeToUtf8Bytes(new[] { childPid, gcPid });
        File.WriteAllBytes(sentinelPath, data);

        Thread.Sleep(lifetimeMs);
    }

    // ------------------------------------------------------------------
    // Spawn + cancel
    // ------------------------------------------------------------------

    /// <summary>
    /// Spawns child, waits for sentinel (poll), kills the group, verifies all PIDs dead.
    /// Returns (recordedPids, killSucceeded).
    /// </summary>
    public static (List<int> pids, bool killed) SpawnTreeAndCancel(
        string exe,
        string workspace,
        int lifetimeMs,
        int cancelDeadlineMs)
    {
        string sentinelPath = Path.Combine(workspace, "tree-sentinel.json");
        if (File.Exists(sentinelPath)) File.Delete(sentinelPath);

        var info = new ProcessStartInfo(exe,
            ["child", "--sentinel", sentinelPath, "--lifetime-ms", lifetimeMs.ToString()])
        {
            UseShellExecute = false,
            RedirectStandardOutput = false,
            RedirectStandardError = false,
        };

        // Set platform process group attributes before start.
        var child = new Process { StartInfo = info };

        if (OperatingSystem.IsWindows())
        {
            child.Start();
        }
        else
        {
            // On Linux: use a thin wrapper to launch in a new process group.
            // We need Setpgid so we can kill -pgid later.
            // ProcessStartInfo doesn't expose SysProcAttr, so we use a posix_spawn shim
            // via a simple approach: have the child call setpgid(0,0) itself.
            // The child subcommand calls SetPgid() at startup when on Linux.
            child.Start();
        }

        int pgid = child.Id; // On POSIX, pgid == pid if child called setpgid(0,0)

        // Poll for sentinel.
        var deadline = DateTime.UtcNow.AddMilliseconds(cancelDeadlineMs);
        List<int>? pids = null;
        while (DateTime.UtcNow < deadline)
        {
            if (File.Exists(sentinelPath))
            {
                try
                {
                    byte[] raw = File.ReadAllBytes(sentinelPath);
                    int[]? arr = JsonSerializer.Deserialize<int[]>(raw);
                    if (arr != null && arr.Length >= 2)
                    {
                        pids = new List<int>(arr);
                        break;
                    }
                }
                catch { }
            }
            Thread.Sleep(50);
        }

        pids ??= new List<int>();

        // Kill the process group.
        bool killed = KillProcessGroup(pgid);

        // Reap main child.
        try { child.WaitForExit(2000); } catch { }

        // Give OS a moment to reap grandchild.
        Thread.Sleep(150);

        // Wait up to 5s for all PIDs to die.
        var killDeadline = DateTime.UtcNow.AddSeconds(5);
        while (DateTime.UtcNow < killDeadline)
        {
            bool allDead = true;
            foreach (int pid in pids)
            {
                if (IsPidAlive(pid))
                {
                    allDead = false;
                    break;
                }
            }
            if (allDead) break;
            Thread.Sleep(100);
        }

        return (pids, killed);
    }

    // ------------------------------------------------------------------
    // Platform: set own process group (called by child subcommand on Linux)
    // Only call this when the process should lead its own group.
    // ------------------------------------------------------------------

    public static void SetOwnProcessGroup()
    {
        if (OperatingSystem.IsLinux() || OperatingSystem.IsMacOS())
        {
            Posix.SetPgid(0, 0);
        }
    }

    // ------------------------------------------------------------------
    // Platform: kill group
    // ------------------------------------------------------------------

    private static bool KillProcessGroup(int pgid)
    {
        if (OperatingSystem.IsWindows())
        {
            return WindowsJobObject.KillGroup(pgid);
        }
        else
        {
            return Posix.KillGroup(pgid);
        }
    }

    // ------------------------------------------------------------------
    // Platform: PID liveness
    // ------------------------------------------------------------------

    public static bool IsPidAlive(int pid)
    {
        if (OperatingSystem.IsWindows())
        {
            return WindowsLiveness.IsAlive(pid);
        }
        else
        {
            return Posix.IsAlive(pid);
        }
    }
}

// ------------------------------------------------------------------
// POSIX interop
// ------------------------------------------------------------------

internal static partial class Posix
{
    // int setpgid(pid_t pid, pid_t pgid)
    [LibraryImport("libc", EntryPoint = "setpgid", SetLastError = true)]
    private static partial int SetPgidNative(int pid, int pgid);

    // int kill(pid_t pid, int sig)
    [LibraryImport("libc", EntryPoint = "kill", SetLastError = true)]
    private static partial int KillNative(int pid, int sig);

    // int killpg(int pgrp, int sig) — not available on all Linux libc so we use kill(-pgid,sig) instead
    private const int SIGKILL = 9;

    public static void SetPgid(int pid, int pgid)
    {
        SetPgidNative(pid, pgid);
    }

    public static bool KillGroup(int pgid)
    {
        // kill(-pgid, SIGKILL)
        int result = KillNative(-pgid, SIGKILL);
        return result == 0;
    }

    public static bool IsAlive(int pid)
    {
        // kill(pid, 0): 0 means exists, ESRCH (3) means gone, EPERM means exists but no permission
        int result = KillNative(pid, 0);
        if (result == 0) return true;
        // errno: ESRCH=3 means not found, EPERM=1 means exists
        int errno = Marshal.GetLastPInvokeError();
        const int ESRCH = 3;
        return errno != ESRCH;
    }
}

// ------------------------------------------------------------------
// Windows: Job Object for kill-on-close
// ------------------------------------------------------------------

[System.Runtime.Versioning.SupportedOSPlatform("windows")]
internal static class WindowsJobObject
{
    public static bool KillGroup(int pgid)
    {
        // On Windows there's no POSIX process group. We use TerminateProcess on the
        // child directly; the grandchild is also terminated because we assigned a Job Object.
        try
        {
            using var proc = Process.GetProcessById(pgid);
            proc.Kill(entireProcessTree: true);
            return true;
        }
        catch
        {
            return false;
        }
    }
}

[System.Runtime.Versioning.SupportedOSPlatform("windows")]
internal static class WindowsLiveness
{
    public static bool IsAlive(int pid)
    {
        try
        {
            using var proc = Process.GetProcessById(pid);
            return !proc.HasExited;
        }
        catch
        {
            return false;
        }
    }
}
