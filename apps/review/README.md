# Qaptr review app

This target is the production native SwiftUI review experience decided by
U3's shell-shape measurement gate (`bench/shell_memory.md`): native SwiftUI,
not Tauri. It hosts the Observation Sheet, Settings, and Onboarding.

## Security and ownership invariants

- `qaptr-review-ffi` is loaded in-process as `libqaptr_review_ffi.dylib`. Before
  opening durable history, it reconciles the configured capture generation:
  the private half is created or read only through the review app's local,
  non-synchronizing Keychain namespace, and only the matching public half is
  written into the vault for the helper. Orphaned or mismatched key halves fail
  closed and are never silently replaced.
- Beyond that bootstrap, the bridge exposes durable-history reads,
  login-item status/registration, and an opaque review-session API. The
  review-session worker opens and decrypts sealed bundles only inside Rust,
  completes local privacy preparation first, and can invoke exactly one
  immutable, selected local CLI provider after a separate just-in-time consent
  decision. Only bounded scalar state crosses the C/Swift boundary. Image
  bytes, credentials, and raw provider responses never do.
- macOS permission APIs are process-scoped, so the review app never asks about
  its own unrelated Screen Recording or Accessibility entries. It reads the
  helper's fresh `permission-status.json` heartbeat and launches that exact
  nested helper in permission-only mode for explicit onboarding requests.
- The review app is the sole owner of Keychain credentials, private
  generation keys, and durable SQLite history writes. The capture helper
  never opens this app's database and never touches the Keychain (KTD5,
  KTD5a, KTD6).
- Choosing or checking a provider in Settings or Onboarding cannot start
  analysis or send capture material. Analysis begins only from the explicit
  Observation Sheet action. Provider dispatch remains behind a second consent
  view that names the provider and model label and summarizes the locally
  prepared text-only payload, eligible capture count, image count, and
  exclusions. OpenRouter analysis is not exposed until its production session
  adapter is wired.
- Onboarding runs at most once per installation
  (`SettingsPreferences.onboardingCompleted`) and never requests a provider
  before its final privacy-consent stage, matching KTD10. The final action is
  disabled when secure generation bootstrap failed, so onboarding cannot claim
  completion while the helper is unable to seal captures.

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
