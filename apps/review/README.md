# Qaptr review app

This target is the production native SwiftUI review experience decided by
U3's shell-shape measurement gate (`bench/shell_memory.md`): native SwiftUI,
not Tauri. It hosts the Observation Sheet, Settings, and Onboarding.

## Security and ownership invariants

- `qaptr-review-ffi` is loaded in-process as `libqaptr_review_ffi.dylib`. It
  exposes only durable-history reads (`qaptr_store_snapshot_json`), permission
  state/request, and login-item status/registration. It has no vault-open,
  decrypt, or provider-invocation entry point, mirroring the capture helper's
  `qaptr-ffi` boundary in the opposite direction.
- The review app is the sole owner of Keychain credentials, private
  generation keys, and durable SQLite history writes. The capture helper
  never opens this app's database and never touches the Keychain (KTD5,
  KTD5a, KTD6).
- No UI affordance in this unit executes anything: every control either reads
  state, writes a local preference, requests a permission, or advances an
  onboarding stage. Choosing a provider in Settings or Onboarding only records
  a local preference; it never invokes `qaptr-provider-cli` or
  `qaptr-provider-openrouter` directly from this unit.
- Onboarding runs at most once per installation
  (`SettingsPreferences.onboardingCompleted`) and never requests a provider
  before its final privacy-consent stage, matching KTD10.

## Build

```sh
apps/review/build_app.sh release
swift test --package-path apps/review
cargo test --manifest-path crates/qaptr-review-ffi/Cargo.toml --all-features
```

The build script compiles the narrow Rust bridge as both a static library and
an in-process dynamic library, then bundles the latter inside the review
app's `Contents/Frameworks/`, exactly mirroring
`apps/helper/build_app.sh`. It also leaves a development-layout symlink beside
the SwiftPM executable and validates that both the development and packaged
paths can be loaded with `dlopen` before returning success.

`ReviewBridge` searches, in order, the explicit
`QAPTR_REVIEW_FFI_LIBRARY_PATH`, `QAPTR_REVIEW_FFI_LIBRARY_DIR`, the packaged
app's `Contents/Frameworks/`, the executable's directory, and finally the
standard loader name. A missing or unloadable library still fails closed.

## Memory measurement

```sh
bash bench/scripts/review_budget.sh --seconds 20
```

See `bench/review_memory.md` for the measured numbers and their scope
limitation relative to the plan's full 24-capture scripted-session budget
assertion (U23).
