# Qaptr

> A quiet, privacy-first work journal for macOS.
>
> Capture the shape of how work gets done, then turn selected moments into clear, reusable workflows.

Qaptr is a native Apple-silicon macOS app with a local capture helper, a review surface, and a Rust core. It is designed for people who want useful workflow memory without handing an always-on recording system their screen.

## What makes it different

- **Occasional, downscaled capture.** Qaptr samples your display on a schedule you control. It is not continuous recording.
- **Local by default.** Captures and review history stay on this Mac until you explicitly start an analysis session.
- **A visible privacy boundary.** Local preparation and redaction happen before the provider consent step. Nothing is sent without an explicit approval.
- **Useful output.** Review observations, identify repeatable work, and turn the result into workflow documents you can edit and export.
- **Native Mac behavior.** The helper owns capture permissions and menu-bar status. The review app owns settings, consent, and review.

## Beta install

Qaptr beta releases are distributed through GitHub Releases as ad-hoc signed Apple-silicon builds. Apple Developer signing and notarization are not required for this private beta path.

```sh
curl -fsSL https://raw.githubusercontent.com/tayoonabule/qaptr/main/scripts/install-beta.sh | bash
```

The installer downloads the newest GitHub prerelease, verifies `SHA256SUMS` when the release provides it, replaces the app in `~/Applications/Qaptr.app`, and prints the installed version and build. macOS may require **Finder → Open** or a one-time approval because beta builds are ad-hoc signed.

To install a specific prerelease:

```sh
QAPTR_BETA_TAG=v0.1.1-beta.1 \
  curl -fsSL https://raw.githubusercontent.com/tayoonabule/qaptr/main/scripts/install-beta.sh | bash
```

For a clean first-run test, uninstall the app and reset its local state through the documented reset procedure before reinstalling. Do not delete application data unless you intend to remove local capture history.

## First run

1. Launch Qaptr and read the capture boundary.
2. Grant Screen Recording to the helper only if you want capture enabled.
3. Choose a capture interval and confirm the menu-bar status.
4. Return to Qaptr to review local progress and history.
5. Connect a supported local CLI provider if you want analysis.
6. Start analysis, inspect the exact prepared boundary, and approve or decline explicitly.

Qaptr does not request an API key for the supported local CLI providers. Provider credentials remain owned by their CLI applications.

## Project status

Qaptr is an active Apple-silicon macOS beta. The Rust core, Swift helper, SwiftUI review app, packaging scripts, and web surface are in this repository. Some hardware-, permission-, provider-, signing-, and notarization-dependent acceptance checks remain environment-specific and are called out as such in the release evidence.

## Development

The workspace pins Rust in [`rust-toolchain.toml`](rust-toolchain.toml). Install the graph indexer once, then use the repository's quality gates:

```sh
uv tool install graphifyy
graphify update .

cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace
cargo doc --workspace --no-deps
swift test --package-path apps/helper
swift test --package-path apps/review
bash packaging/release.sh --dry-run --skip-reproducibility
```

The packaged app is written to `packaging/.build/Qaptr.app`. Build output and release evidence are local artifacts and are not tracked.

## Architecture

```text
Qaptr.app
├── native SwiftUI review app
│   ├── settings and onboarding
│   ├── local history and workflow review
│   └── explicit analysis consent
└── QaptrHelper login item
    ├── Screen Recording and Accessibility boundary
    ├── scheduled capture and sealing
    └── menu-bar status and controls

Rust workspace
├── privacy classification and redaction
├── provider/runtime policy
├── durable history and workflow models
└── Swift FFI boundaries
```

The helper owns the process-scoped macOS permissions that it actually uses. The review app reads the helper's scalar status rather than claiming a permission it does not hold.

## Privacy and security

Read [`docs/privacy.md`](docs/privacy.md), [`SECURITY.md`](SECURITY.md), and [`docs/release-process.md`](docs/release-process.md) before enabling capture or publishing a build. Please do not include screenshots, credentials, database files, crash dumps, or private machine paths in issues or pull requests.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Small, focused pull requests are preferred. Changes to shipped behavior require release evidence and a monotonic build number when they merge to `main`.

## Releases

- [`CHANGELOG.md`](CHANGELOG.md) records user-visible changes.
- [`docs/release-process.md`](docs/release-process.md) is the canonical release procedure.
- [`docs/release.md`](docs/release.md) records evidence and blocked boundaries.
- GitHub prereleases are the beta distribution channel.

## License

Qaptr is released under the [MIT License](LICENSE).