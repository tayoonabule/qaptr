# Contributing to Qaptr

Thanks for helping improve Qaptr. The project is a Rust workspace with native Swift macOS apps and a small web surface.

## Before opening a pull request

- Read `AGENTS.md` and use the knowledge graph before broad code searches.
- Keep changes focused and avoid committing generated build output, screenshots, databases, crash dumps, credentials, or machine-specific paths.
- Preserve the privacy boundary. Do not add telemetry, credential reads, hidden provider dispatch, or permission claims without a corresponding design and test.
- Add or update tests for changed behavior.

## Required checks

```sh
cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace
cargo doc --workspace --no-deps
swift test --package-path apps/helper
swift test --package-path apps/review
```

For packaging changes, also run:

```sh
bash packaging/release.sh --dry-run --skip-reproducibility
bash bench/scripts/packaged_fixture_smoke.sh
```

## Pull requests

Explain the user-visible change, the privacy impact, the tests run, and any environment-dependent checks that remain blocked. Changes to shipped behavior need release evidence before merging to `main`.
