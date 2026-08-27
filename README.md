# Qaptr

Qaptr is a local-first Rust workspace for capturing workflow context, preparing
it with a fail-closed privacy boundary, and producing useful structured review
material. The repository also contains the public marketing and waitlist site
under `web/`.

## Core guarantees

- Screen material is handled locally by the Rust macOS adapters and vault.
- OCR and Vision recognition happen locally before any provider boundary.
- The privacy gate refuses to emit data when recognition, masking, sanitization,
  or budget checks fail.
- Vault records are encrypted and retained according to explicit policy.

## Development

```sh
cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace
cargo doc --workspace --no-deps
npm --prefix web ci
npm --prefix web run build
```

## Repository layout

```text
crates/qaptr-macos/    macOS OCR, Vision, credentials, and image adapters
crates/qaptr-privacy/  PII recognition, masking, sanitization, and fail-closed gate
crates/qaptr-vault/    encrypted capture bundles and retention
crates/qaptr-workflow/ review analysis and export domain logic
crates/qaptr-ffi/      narrow Rust C ABI for the capture/vault boundary
web/                   Astro marketing and waitlist site
```

The former native Swift applications and macOS review UI are intentionally not
part of this clean-start branch.
