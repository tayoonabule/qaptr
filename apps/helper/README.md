# Qaptr capture helper

This target is the production `LSUIElement` capture helper, not a second
capture implementation. It retains the U4 decision to use one-shot,
pre-scaled, in-process ScreenCaptureKit calls with `queueDepth = 1` and one
display at a time.

## Security and ownership invariants

- The helper owns one process-wide lock at
  `~/Library/Application Support/Qaptr/helper.lock`. A second helper exits;
  it never starts a second ScreenCaptureKit owner.
- `CaptureCoordinator` has a single-flight gate. A tick that arrives while a
  capture or seal is still running is refused immediately, not queued. Display
  captures within one tick are sequential.
- `qaptr-ffi` is loaded in-process as `libqaptr_ffi.dylib`. It exposes vault
  creation, public-key lookup, sealing, and destruction only. It has no open,
  decrypt, credential, or private-key entry point.
- The helper therefore holds only the generation id and generation **public**
  key. It never links the Keychain adapter and never receives a private key.
  The review app is the only owner of Keychain credentials and vault reads.
- Screen Recording permission is checked immediately before every tick. If it
  is revoked, the helper logs a quiet skip and resumes checking on later ticks.
- Screen Recording and Accessibility are owned, requested, and preflighted by
  this helper process. It publishes only their booleans, its PID, and a
  timestamp to `permission-status.json`; the review app accepts that record
  only while it is fresh and the helper is alive.
- Onboarding can launch the helper in `--permission-only true` mode. That mode
  can request and report permissions but cannot capture. The review app sends
  an explicit `startCapture` command only after the final consent step.
- `TickPlanner` resets the next due time from the current monotonic time after
  every fire. Sleep, wake, or a slow capture cannot create a catch-up burst.

## Build

```sh
apps/helper/build_app.sh release
swift test --package-path apps/helper
cargo test --manifest-path crates/qaptr-ffi/Cargo.toml --all-features
```

The build script compiles the narrow Rust bridge as both a static library and
an in-process dynamic library, then bundles the latter inside the helper app.
No child process is launched for a capture.
