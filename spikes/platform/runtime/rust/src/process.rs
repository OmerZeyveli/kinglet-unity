//! Process-tree management for the host probe.
//!
//! POSIX: children are launched into a fresh process group (`setsid`-style via
//! `setpgid`) so the whole tree can be killed with `killpg`. Windows: children
//! are placed in a Job Object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`.
//!
//! The Windows path is behind `#[cfg(windows)]` and is not compiled on this
//! Linux host — that is expected and fine for the spike.

use std::io;
use std::path::Path;
use std::process::{Child, Command, Stdio};

/// A spawned child tree plus the handle needed to terminate it as a group.
pub struct SpawnedTree {
    pub child: Child,
    /// POSIX process-group id (== child pid, since the child leads a new group).
    #[cfg(unix)]
    pub pgid: i32,
    #[cfg(windows)]
    pub job: windows_impl::JobHandle,
}

/// Spawn `exe child --sentinel <sentinel> --lifetime-ms <lifetime_ms>` in its
/// own killable group/job.
pub fn spawn_child_tree(
    exe: &Path,
    sentinel: &Path,
    lifetime_ms: u64,
) -> io::Result<SpawnedTree> {
    let mut cmd = Command::new(exe);
    cmd.arg("child")
        .arg("--sentinel")
        .arg(sentinel)
        .arg("--lifetime-ms")
        .arg(lifetime_ms.to_string())
        .stdout(Stdio::null())
        .stderr(Stdio::null());

    #[cfg(unix)]
    {
        unix_impl::configure_new_process_group(&mut cmd);
        let child = cmd.spawn()?;
        let pgid = child.id() as i32;
        Ok(SpawnedTree { child, pgid })
    }

    #[cfg(windows)]
    {
        let job = windows_impl::create_kill_on_close_job()?;
        let child = cmd.spawn()?;
        windows_impl::assign_process_to_job(&job, &child)?;
        Ok(SpawnedTree { child, job })
    }

    #[cfg(not(any(unix, windows)))]
    {
        let _ = (exe, sentinel, lifetime_ms);
        Err(io::Error::new(
            io::ErrorKind::Unsupported,
            "unsupported platform",
        ))
    }
}

/// Spawn `exe child --sentinel <sentinel> --lifetime-ms <lifetime_ms>` as a
/// plain child that INHERITS the caller's process group / job. Used by the
/// `child` subcommand to launch its grandchild, so a `killpg` on the top-level
/// group (or a Job-Object teardown) reaches the grandchild too.
pub fn spawn_child_inheriting_group(
    exe: &Path,
    sentinel: &Path,
    lifetime_ms: u64,
) -> io::Result<std::process::Child> {
    Command::new(exe)
        .arg("child")
        .arg("--sentinel")
        .arg(sentinel)
        .arg("--lifetime-ms")
        .arg(lifetime_ms.to_string())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
}

/// Kill the entire spawned tree. Returns `Ok(())` only if the kill syscall
/// itself succeeded (or the group was already gone).
pub fn kill_tree(tree: &SpawnedTree) -> io::Result<()> {
    #[cfg(unix)]
    {
        unix_impl::kill_process_group(tree.pgid)
    }
    #[cfg(windows)]
    {
        windows_impl::terminate_job(&tree.job)
    }
    #[cfg(not(any(unix, windows)))]
    {
        let _ = tree;
        Err(io::Error::new(
            io::ErrorKind::Unsupported,
            "unsupported platform",
        ))
    }
}

/// Whether a PID currently refers to a live process.
pub fn is_pid_alive(pid: i32) -> bool {
    #[cfg(unix)]
    {
        unix_impl::is_pid_alive(pid)
    }
    #[cfg(windows)]
    {
        windows_impl::is_pid_alive(pid as u32)
    }
    #[cfg(not(any(unix, windows)))]
    {
        let _ = pid;
        false
    }
}

// ---------------------------------------------------------------------------
// POSIX implementation
// ---------------------------------------------------------------------------

#[cfg(unix)]
mod unix_impl {
    use std::io;
    use std::os::unix::process::CommandExt;
    use std::process::Command;

    // libc bindings, declared directly to avoid an extra crate dependency.
    unsafe extern "C" {
        fn setpgid(pid: i32, pgid: i32) -> i32;
        fn killpg(pgrp: i32, sig: i32) -> i32;
        fn kill(pid: i32, sig: i32) -> i32;
    }

    const SIGKILL: i32 = 9;
    const ESRCH: i32 = 3;
    const EPERM: i32 = 1;

    /// Put the child in its own process group (pgid == its own pid) via a
    /// pre-exec hook, so `killpg` reaches the child and every descendant that
    /// inherits the group.
    pub fn configure_new_process_group(cmd: &mut Command) {
        unsafe {
            cmd.pre_exec(|| {
                // 0,0 => set this process's pgid to its own pid.
                if setpgid(0, 0) != 0 {
                    return Err(io::Error::last_os_error());
                }
                Ok(())
            });
        }
    }

    /// SIGKILL the whole process group. Treats "no such group" as success.
    pub fn kill_process_group(pgid: i32) -> io::Result<()> {
        let rc = unsafe { killpg(pgid, SIGKILL) };
        if rc == 0 {
            return Ok(());
        }
        let err = io::Error::last_os_error();
        match err.raw_os_error() {
            Some(ESRCH) => Ok(()), // already gone
            _ => Err(err),
        }
    }

    /// `kill(pid, 0)` probes existence without sending a signal.
    pub fn is_pid_alive(pid: i32) -> bool {
        let rc = unsafe { kill(pid, 0) };
        if rc == 0 {
            return true;
        }
        match io::Error::last_os_error().raw_os_error() {
            Some(ESRCH) => false, // no such process
            Some(EPERM) => true,  // exists, we just can't signal it
            _ => true,
        }
    }
}

// ---------------------------------------------------------------------------
// Windows implementation (not compiled on this Linux host)
// ---------------------------------------------------------------------------

#[cfg(windows)]
mod windows_impl {
    use std::io;
    use std::os::windows::io::AsRawHandle;
    use std::process::Child;

    // Minimal Win32 bindings for Job Objects.
    #[allow(non_camel_case_types)]
    type HANDLE = *mut core::ffi::c_void;
    #[allow(non_camel_case_types)]
    type BOOL = i32;
    #[allow(non_camel_case_types)]
    type DWORD = u32;

    const JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE: DWORD = 0x2000;
    const JobObjectExtendedLimitInformation: i32 = 9;
    const PROCESS_ALL_ACCESS: DWORD = 0x1F0FFF;
    const STILL_ACTIVE: DWORD = 259;

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
        per_process_user_time_limit: i64,
        per_job_user_time_limit: i64,
        limit_flags: DWORD,
        minimum_working_set_size: usize,
        maximum_working_set_size: usize,
        active_process_limit: DWORD,
        affinity: usize,
        priority_class: DWORD,
        scheduling_class: DWORD,
    }

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct IO_COUNTERS {
        read_operation_count: u64,
        write_operation_count: u64,
        other_operation_count: u64,
        read_transfer_count: u64,
        write_transfer_count: u64,
        other_transfer_count: u64,
    }

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
        basic_limit_information: JOBOBJECT_BASIC_LIMIT_INFORMATION,
        io_info: IO_COUNTERS,
        process_memory_limit: usize,
        job_memory_limit: usize,
        peak_process_memory_used: usize,
        peak_job_memory_used: usize,
    }

    unsafe extern "system" {
        fn CreateJobObjectW(attrs: *mut core::ffi::c_void, name: *const u16) -> HANDLE;
        fn SetInformationJobObject(
            job: HANDLE,
            class: i32,
            info: *const core::ffi::c_void,
            len: DWORD,
        ) -> BOOL;
        fn AssignProcessToJobObject(job: HANDLE, process: HANDLE) -> BOOL;
        fn TerminateJobObject(job: HANDLE, exit_code: DWORD) -> BOOL;
        fn CloseHandle(h: HANDLE) -> BOOL;
        fn OpenProcess(access: DWORD, inherit: BOOL, pid: DWORD) -> HANDLE;
        fn GetExitCodeProcess(process: HANDLE, code: *mut DWORD) -> BOOL;
    }

    /// RAII wrapper around a job handle.
    pub struct JobHandle(HANDLE);

    impl Drop for JobHandle {
        fn drop(&mut self) {
            if !self.0.is_null() {
                unsafe {
                    CloseHandle(self.0);
                }
            }
        }
    }

    pub fn create_kill_on_close_job() -> io::Result<JobHandle> {
        let job = unsafe { CreateJobObjectW(core::ptr::null_mut(), core::ptr::null()) };
        if job.is_null() {
            return Err(io::Error::last_os_error());
        }
        let mut info: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = unsafe { core::mem::zeroed() };
        info.basic_limit_information.limit_flags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        let ok = unsafe {
            SetInformationJobObject(
                job,
                JobObjectExtendedLimitInformation,
                &info as *const _ as *const core::ffi::c_void,
                core::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as DWORD,
            )
        };
        if ok == 0 {
            let err = io::Error::last_os_error();
            unsafe {
                CloseHandle(job);
            }
            return Err(err);
        }
        Ok(JobHandle(job))
    }

    pub fn assign_process_to_job(job: &JobHandle, child: &Child) -> io::Result<()> {
        let handle = child.as_raw_handle() as HANDLE;
        let ok = unsafe { AssignProcessToJobObject(job.0, handle) };
        if ok == 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(())
    }

    pub fn terminate_job(job: &JobHandle) -> io::Result<()> {
        let ok = unsafe { TerminateJobObject(job.0, 1) };
        if ok == 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(())
    }

    pub fn is_pid_alive(pid: u32) -> bool {
        let handle = unsafe { OpenProcess(PROCESS_ALL_ACCESS, 0, pid) };
        if handle.is_null() {
            return false;
        }
        let mut code: DWORD = 0;
        let ok = unsafe { GetExitCodeProcess(handle, &mut code) };
        unsafe {
            CloseHandle(handle);
        }
        ok != 0 && code == STILL_ACTIVE
    }
}
