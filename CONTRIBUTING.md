# Contributing to Qaptr

Qaptr is a Rust workspace with a small Astro web surface. Native Swift
applications and macOS review UI are intentionally out of scope for this
clean-start branch.

## Before opening a pull request

Run the Rust gates and the website build:

```sh
cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace
cargo doc --workspace --no-deps
npm --prefix web ci
npm --prefix web run build
```

Keep privacy behavior fail-closed. Changes to capture, recognition, vault, or
provider boundaries should include focused tests for both success and refusal
paths.
