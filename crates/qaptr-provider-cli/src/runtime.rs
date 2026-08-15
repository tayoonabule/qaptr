//! Sandboxed, bounded subprocess execution for local CLI adapters.
//!
//! The process lifecycle is intentionally kept in one module because spawn,
//! pipe draining, timeout cancellation, cleanup, and sandbox-profile creation
//! share invariants that would be easy to break across loosely coupled helper
//! modules. The public surface remains small despite this implementation size.

use std::{
    ffi::OsString,
    io::{self, Read, Write},
    num::NonZeroUsize,
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use qaptr_provider::{ExecutablePath, ProviderError, ProviderId, RuntimeFailureKind};
use thiserror::Error;

const SANDBOX_EXEC: &str = "/usr/bin/sandbox-exec";
const KILL: &str = "/bin/kill";
const POLL_INTERVAL: Duration = Duration::from_millis(5);
const WORKDIR_ATTEMPTS: u32 = 128;

/// A non-zero wall-clock limit for one child invocation.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Timeout(Duration);

impl Timeout {
    /// Creates a timeout and rejects a zero duration.
    pub fn new(duration: Duration) -> Result<Self, CliRuntimeError> {
        if duration.is_zero() {
            return Err(CliRuntimeError::InvalidLimit { kind: "timeout" });
        }
        Ok(Self(duration))
    }

    /// Returns the duration represented by this limit.
    pub const fn duration(self) -> Duration {
        self.0
    }
}

/// A non-zero upper bound on combined stdout and stderr bytes retained.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct OutputLimit(NonZeroUsize);

impl OutputLimit {
    /// Creates an output limit and rejects zero bytes.
    pub fn new(bytes: usize) -> Result<Self, CliRuntimeError> {
        NonZeroUsize::new(bytes)
            .map(Self)
            .ok_or(CliRuntimeError::InvalidLimit { kind: "output" })
    }

    /// Returns the byte limit.
    pub const fn bytes(self) -> usize {
        self.0.get()
    }
}

/// The resource limits applied to every CLI invocation.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RuntimeLimits {
    timeout: Timeout,
    output: OutputLimit,
}

impl RuntimeLimits {
    /// Creates a limit set for child wall time and captured output.
    pub const fn new(timeout: Timeout, output: OutputLimit) -> Self {
        Self { timeout, output }
    }

    /// Returns the wall-clock limit.
    pub const fn timeout(self) -> Timeout {
        self.timeout
    }

    /// Returns the output limit.
    pub const fn output(self) -> OutputLimit {
        self.output
    }
}

/// A command invocation with direct arguments and an explicit environment.
///
/// The command line is represented as separate operating-system arguments.
/// This type intentionally has no method that accepts a shell command string.
#[derive(Clone, Debug)]
pub struct CliInvocation {
    executable: ExecutablePath,
    args: Vec<OsString>,
    stdin: Vec<u8>,
    environment: Vec<(OsString, OsString)>,
    support_paths: Vec<PathBuf>,
}

impl CliInvocation {
    /// Starts an invocation for an absolute executable path.
    pub fn new(executable: ExecutablePath) -> Self {
        Self {
            executable,
            args: Vec::new(),
            stdin: Vec::new(),
            environment: Vec::new(),
            support_paths: Vec::new(),
        }
    }

    /// Adds one direct argument without shell parsing.
    pub fn arg(mut self, argument: impl Into<OsString>) -> Self {
        self.args.push(argument.into());
        self
    }

    /// Replaces the prompt or input sent to the child's stdin.
    pub fn stdin(mut self, input: impl Into<Vec<u8>>) -> Self {
        self.stdin = input.into();
        self
    }

    /// Adds one explicit environment variable.
    pub fn environment(mut self, key: impl Into<OsString>, value: impl Into<OsString>) -> Self {
        self.environment.push((key.into(), value.into()));
        self
    }

    /// Allows a provider's documented support directory to be read.
    pub fn support_path(mut self, path: impl Into<PathBuf>) -> Self {
        self.support_paths.push(path.into());
        self
    }
}

/// Captured output from a successful child process.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CliOutput {
    stdout: Vec<u8>,
    stderr: Vec<u8>,
}

impl CliOutput {
    /// Creates captured output for an in-process adapter executor or test fake.
    pub fn new(stdout: impl Into<Vec<u8>>, stderr: impl Into<Vec<u8>>) -> Self {
        Self {
            stdout: stdout.into(),
            stderr: stderr.into(),
        }
    }

    /// Returns captured standard output.
    pub fn stdout(&self) -> &[u8] {
        &self.stdout
    }

    /// Returns captured standard error.
    pub fn stderr(&self) -> &[u8] {
        &self.stderr
    }
}

/// Errors raised by the isolated runtime before provider normalization.
#[derive(Debug, Error)]
pub enum CliRuntimeError {
    /// The executable path does not identify an existing regular file.
    #[error("CLI executable is not installed: {path}")]
    NotInstalled {
        /// The missing executable.
        path: String,
    },
    /// A configured limit was zero.
    #[error("{kind} limit must be greater than zero")]
    InvalidLimit {
        /// The rejected limit name.
        kind: &'static str,
    },
    /// A profile path could not be represented safely in the sandbox DSL.
    #[error("sandbox path is not valid UTF-8: {path}")]
    InvalidSandboxPath {
        /// The path that could not be represented.
        path: PathBuf,
    },
    /// The sandbox executable could not be started.
    #[error("could not start sandbox-exec: {source}")]
    SandboxUnavailable {
        /// Underlying spawn error.
        #[source]
        source: io::Error,
    },
    /// A child process could not be started.
    #[error("could not start CLI process: {source}")]
    Spawn {
        /// Underlying spawn error.
        #[source]
        source: io::Error,
    },
    /// A child exceeded the output budget.
    #[error("CLI output exceeded the {limit} byte limit")]
    OutputLimitExceeded {
        /// Configured byte limit.
        limit: usize,
        /// Bounded standard output retained before termination.
        stdout: Vec<u8>,
        /// Bounded standard error retained before termination.
        stderr: Vec<u8>,
    },
    /// A child exceeded the wall-clock budget.
    #[error("CLI process exceeded its timeout")]
    TimedOut,
    /// The child was terminated by the caller.
    #[error("CLI process was cancelled")]
    Cancelled,
    /// A child exited unsuccessfully.
    #[error("CLI process exited unsuccessfully with status {code:?}")]
    NonZeroExit {
        /// Portable exit code, when one was provided by the operating system.
        code: Option<i32>,
        /// Bounded standard output captured before returning the failure.
        stdout: Vec<u8>,
        /// Bounded standard error captured before returning the failure.
        stderr: Vec<u8>,
    },
    /// A pipe reader or stdin writer failed.
    #[error("CLI {stream} pipe failed: {source}")]
    Pipe {
        /// Pipe name.
        stream: &'static str,
        /// Underlying I/O error.
        #[source]
        source: io::Error,
    },
    /// The runtime could not create or remove its isolated directory.
    #[error("CLI working directory operation failed for {path}: {source}")]
    WorkingDirectory {
        /// Directory involved in the operation.
        path: PathBuf,
        /// Underlying filesystem error.
        #[source]
        source: io::Error,
    },
    /// A reader thread failed to return its result.
    #[error("CLI output reader thread failed")]
    ReaderThread,
}

impl CliRuntimeError {
    /// Maps the runtime error onto U13's typed provider taxonomy.
    pub fn into_provider_error(self, provider: &ProviderId) -> ProviderError {
        let kind = match self {
            Self::NotInstalled { .. } => {
                return ProviderError::NotInstalled {
                    provider: provider.clone(),
                };
            }
            Self::TimedOut => RuntimeFailureKind::TimedOut,
            Self::Cancelled => RuntimeFailureKind::Cancelled,
            Self::InvalidLimit { .. }
            | Self::InvalidSandboxPath { .. }
            | Self::SandboxUnavailable { .. }
            | Self::Spawn { .. }
            | Self::OutputLimitExceeded { .. }
            | Self::NonZeroExit { .. }
            | Self::Pipe { .. }
            | Self::WorkingDirectory { .. }
            | Self::ReaderThread => RuntimeFailureKind::Invocation,
        };
        ProviderError::RuntimeFailure {
            provider: provider.clone(),
            kind,
        }
    }
}

/// Runs local CLI commands under the U14 isolation contract.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CliRuntime {
    limits: RuntimeLimits,
}

impl CliRuntime {
    /// Creates a runtime with fixed limits used for all subsequent invocations.
    pub const fn new(limits: RuntimeLimits) -> Self {
        Self { limits }
    }

    /// Runs an invocation and exposes detailed runtime errors to an adapter.
    pub fn run(&self, invocation: CliInvocation) -> Result<CliOutput, CliRuntimeError> {
        let executable = Path::new(invocation.executable.as_str());
        ensure_executable(executable)?;
        let working_directory = WorkingDirectory::create()?;
        let profile = sandbox_profile(
            executable,
            &working_directory.path,
            &invocation.support_paths,
        )?;

        let mut command = Command::new(SANDBOX_EXEC);
        command
            .arg("-p")
            .arg(profile)
            .arg(executable)
            .args(&invocation.args)
            .env_clear()
            .env("TMPDIR", &working_directory.path)
            .current_dir(&working_directory.path)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        for (key, value) in &invocation.environment {
            command.env(key, value);
        }
        configure_process_group(&mut command);

        let mut child = command.spawn().map_err(|source| {
            if source.kind() == io::ErrorKind::NotFound {
                CliRuntimeError::SandboxUnavailable { source }
            } else {
                CliRuntimeError::Spawn { source }
            }
        })?;
        let stdin = child.stdin.take();
        let input = invocation.stdin;
        let writer = thread::spawn(move || write_stdin(stdin, &input));

        let output_exceeded = Arc::new(AtomicBool::new(false));
        let stdout = spawn_reader(
            child.stdout.take(),
            self.limits.output.bytes(),
            Arc::clone(&output_exceeded),
            "stdout",
        );
        let stderr = spawn_reader(
            child.stderr.take(),
            self.limits.output.bytes(),
            Arc::clone(&output_exceeded),
            "stderr",
        );
        let deadline = Instant::now() + self.limits.timeout.duration();
        let mut timed_out = false;
        let status = loop {
            if output_exceeded.load(Ordering::Acquire) {
                terminate_process_tree(&mut child);
                break None;
            }
            match child.try_wait().map_err(|source| CliRuntimeError::Pipe {
                stream: "status",
                source,
            })? {
                Some(status) => break Some(status),
                None if Instant::now() >= deadline => {
                    timed_out = true;
                    terminate_process_tree(&mut child);
                    break None;
                }
                None => thread::sleep(POLL_INTERVAL),
            }
        };

        let status = match status {
            Some(status) => status,
            None => child.wait().map_err(|source| CliRuntimeError::Pipe {
                stream: "status",
                source,
            })?,
        };
        let writer_result = writer.join().map_err(|_| CliRuntimeError::ReaderThread)?;
        if let Err(source) = writer_result
            && source.kind() != io::ErrorKind::BrokenPipe
        {
            return Err(CliRuntimeError::Pipe {
                stream: "stdin",
                source,
            });
        }
        let stdout = stdout.join().map_err(|_| CliRuntimeError::ReaderThread)??;
        let stderr = stderr.join().map_err(|_| CliRuntimeError::ReaderThread)??;

        if timed_out {
            return Err(CliRuntimeError::TimedOut);
        }
        if output_exceeded.load(Ordering::Acquire)
            || stdout.len().saturating_add(stderr.len()) > self.limits.output.bytes()
        {
            return Err(CliRuntimeError::OutputLimitExceeded {
                limit: self.limits.output.bytes(),
                stdout,
                stderr,
            });
        }
        if !status.success() {
            return Err(CliRuntimeError::NonZeroExit {
                code: status.code(),
                stdout,
                stderr,
            });
        }
        Ok(CliOutput { stdout, stderr })
    }

    /// Runs an invocation and maps failures onto U13's provider taxonomy.
    pub fn run_for_provider(
        &self,
        provider: &ProviderId,
        invocation: CliInvocation,
    ) -> Result<CliOutput, ProviderError> {
        self.run(invocation)
            .map_err(|error| error.into_provider_error(provider))
    }
}

fn ensure_executable(path: &Path) -> Result<(), CliRuntimeError> {
    match std::fs::metadata(path) {
        Ok(metadata) if metadata.is_file() => Ok(()),
        Ok(_) => Err(CliRuntimeError::NotInstalled {
            path: path.to_string_lossy().into_owned(),
        }),
        Err(source) if source.kind() == io::ErrorKind::NotFound => {
            Err(CliRuntimeError::NotInstalled {
                path: path.to_string_lossy().into_owned(),
            })
        }
        Err(source) => Err(CliRuntimeError::Pipe {
            stream: "executable metadata",
            source,
        }),
    }
}

fn write_stdin(stdin: Option<std::process::ChildStdin>, input: &[u8]) -> io::Result<()> {
    let Some(mut stdin) = stdin else {
        return Ok(());
    };
    stdin.write_all(input)
}

fn spawn_reader(
    pipe: Option<impl Read + Send + 'static>,
    limit: usize,
    output_exceeded: Arc<AtomicBool>,
    stream: &'static str,
) -> thread::JoinHandle<Result<Vec<u8>, CliRuntimeError>> {
    thread::spawn(move || {
        let Some(mut pipe) = pipe else {
            return Ok(Vec::new());
        };
        read_output(&mut pipe, limit, &output_exceeded)
            .map_err(|source| CliRuntimeError::Pipe { stream, source })
    })
}

fn read_output(
    pipe: &mut impl Read,
    limit: usize,
    output_exceeded: &AtomicBool,
) -> io::Result<Vec<u8>> {
    let mut output = Vec::new();
    let mut buffer = [0_u8; 8 * 1024];
    loop {
        if output.len() == limit {
            let mut probe = [0_u8; 1];
            let read = pipe.read(&mut probe)?;
            if read > 0 {
                output_exceeded.store(true, Ordering::Release);
            }
            break;
        }
        let read_limit = (limit - output.len()).min(buffer.len());
        let read = pipe.read(&mut buffer[..read_limit])?;
        if read == 0 {
            break;
        }
        output.extend_from_slice(&buffer[..read]);
    }
    Ok(output)
}

struct WorkingDirectory {
    path: PathBuf,
}

impl WorkingDirectory {
    fn create() -> Result<Self, CliRuntimeError> {
        let root = std::env::temp_dir();
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|_| CliRuntimeError::WorkingDirectory {
                path: root.clone(),
                source: io::Error::other("system clock precedes Unix epoch"),
            })?
            .as_nanos();
        for attempt in 0..WORKDIR_ATTEMPTS {
            let path = root.join(format!(
                "qaptr-cli-{}-{stamp}-{attempt}",
                std::process::id()
            ));
            match std::fs::create_dir(&path) {
                Ok(()) => return Ok(Self { path }),
                Err(source) if source.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(source) => {
                    return Err(CliRuntimeError::WorkingDirectory { path, source });
                }
            }
        }
        Err(CliRuntimeError::WorkingDirectory {
            path: root,
            source: io::Error::new(
                io::ErrorKind::AlreadyExists,
                "could not allocate unique directory",
            ),
        })
    }
}

impl Drop for WorkingDirectory {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.path);
    }
}

fn sandbox_profile(
    executable: &Path,
    working_directory: &Path,
    support_paths: &[PathBuf],
) -> Result<String, CliRuntimeError> {
    let mut profile = String::from(
        "(version 1)\n\
(deny default)\n\
(allow process*)\n\
(allow process-exec)\n\
(allow sysctl-read)\n\
(allow file-read*)\n\
(allow file-map-executable)\n\
(allow network-outbound)\n",
    );
    if let Some(home) = std::env::var_os("HOME").map(PathBuf::from) {
        append_deny_subpath(&mut profile, "file-read*", &home)?;
        append_deny_subpath(&mut profile, "file-write*", &home)?;
    }
    append_deny_subpath(&mut profile, "file-read*", Path::new("/Volumes"))?;
    append_deny_subpath(&mut profile, "file-write*", Path::new("/Volumes"))?;
    // These are explicit exceptions to the home deny rule above. Keeping the
    // allows after the deny is important when TMPDIR itself lives under HOME.
    append_allow_subpath(&mut profile, "file-read*", working_directory)?;
    append_allow_subpath(&mut profile, "file-write*", working_directory)?;
    append_allow_literal(&mut profile, "file-read*", executable)?;
    append_allow_literal(&mut profile, "file-map-executable", executable)?;
    for path in support_paths {
        if !path.is_absolute() {
            return Err(CliRuntimeError::InvalidSandboxPath { path: path.clone() });
        }
        append_allow_subpath(&mut profile, "file-read*", path)?;
        append_allow_subpath(&mut profile, "file-map-executable", path)?;
    }
    Ok(profile)
}

fn append_allow_subpath(
    profile: &mut String,
    operation: &str,
    path: &Path,
) -> Result<(), CliRuntimeError> {
    append_path_rule(profile, "allow", operation, "subpath", path)
}

fn append_allow_literal(
    profile: &mut String,
    operation: &str,
    path: &Path,
) -> Result<(), CliRuntimeError> {
    append_path_rule(profile, "allow", operation, "literal", path)
}

fn append_deny_subpath(
    profile: &mut String,
    operation: &str,
    path: &Path,
) -> Result<(), CliRuntimeError> {
    append_path_rule(profile, "deny", operation, "subpath", path)
}

fn append_path_rule(
    profile: &mut String,
    action: &str,
    operation: &str,
    matcher: &str,
    path: &Path,
) -> Result<(), CliRuntimeError> {
    let path = path
        .to_str()
        .ok_or_else(|| CliRuntimeError::InvalidSandboxPath {
            path: path.to_path_buf(),
        })?;
    profile.push_str(&format!(
        "({action} {operation} ({matcher} \"{}\"))\n",
        escape_profile_string(path)
    ));
    Ok(())
}

fn escape_profile_string(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
}

fn configure_process_group(command: &mut Command) {
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;

        command.process_group(0);
    }
}

fn terminate_process_tree(child: &mut Child) {
    let pid = child.id();
    let _ = Command::new(KILL)
        .arg("-KILL")
        .arg(format!("-{pid}"))
        .env_clear()
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    let _ = child.kill();
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::{escape_profile_string, sandbox_profile};

    #[test]
    fn profile_string_escapes_seatbelt_delimiters() {
        assert_eq!(escape_profile_string("a\\b\"c\nd"), "a\\\\b\\\"c\\nd");
    }

    #[test]
    fn working_directory_allow_follows_home_deny() {
        let home = std::env::var_os("HOME").expect("test has a home directory");
        let home = PathBuf::from(home);
        let working_directory = home.join("qaptr-test-working-directory");
        let profile = sandbox_profile(std::path::Path::new("/bin/echo"), &working_directory, &[])
            .expect("test paths are valid sandbox paths");
        let home_deny = format!(
            "(deny file-write* (subpath \"{}\"))",
            home.to_str().expect("test home is UTF-8")
        );
        let working_allow = format!(
            "(allow file-write* (subpath \"{}\"))",
            working_directory
                .to_str()
                .expect("test working directory is UTF-8")
        );
        assert!(
            profile.find(&home_deny).expect("home deny is present")
                < profile
                    .find(&working_allow)
                    .expect("working-directory exception is present")
        );
    }
}
