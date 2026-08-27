# Working in this repository

Qaptr is a Rust workspace with a small Astro website. The native Swift
applications and macOS review UI were removed for the clean-start branch.

## Knowledge graph first

The repository is indexed as a knowledge graph in `graphify-out/`. Query the
graph before grepping or reading files when investigating structure:

```sh
graphify query "how does the privacy gate enforce redaction?"
graphify explain "PrivacyGate"
graphify path "AnalysisRunner" "Vault"
graphify affected "ContextSnapshot" --depth 2
graphify update .
```

Run `graphify affected "<symbol>"` before changing shared types, and run
`graphify update .` after edits. Fall back to `rg` for literals, configuration,
comments, or files the extractor skipped.

## Parallel agents

Refresh the graph before and after edits. Scope work with `query` and
`affected`, avoid colliding on shared hubs, and cite `file:line` provenance when
reporting structural findings.

## Quality gates

Run these before handing work back:

```sh
cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace
cargo doc --workspace --no-deps
npm --prefix web ci
npm --prefix web run build
```

Preserve the fail-closed privacy guarantees, encrypted vault boundaries, and
bounded data contracts. Changes to capture, recognition, sanitization, or
provider boundaries need focused success and refusal-path tests.
