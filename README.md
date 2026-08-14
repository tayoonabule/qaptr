# Qaptr

A lightweight, privacy-first macOS app that helps people capture how work gets done and turn it into reusable workflow documents for automation, sharing, onboarding, and SOPs.

Qaptr is currently in staged implementation. See [`docs/plans/qaptr-v1.md`](docs/plans/qaptr-v1.md) for the ambiguity-resolved v1 product contract.

## Status

Private pre-development project targeting Apple-silicon macOS with a Rust-first architecture. U1 establishes the pinned Rust workspace, CI quality gates, and the platform-independent `qaptr-domain` vocabulary. Later units add ports and platform adapters without putting macOS or I/O types in the domain crate.

## Development

The repository pins Rust in [`rust-toolchain.toml`](rust-toolchain.toml). Run the same gates as CI with:

```sh
cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace
cargo doc --workspace --no-deps
```

## Codebase map

The workspace is indexed as a knowledge graph so navigation does not depend on
grepping. Install the indexer once and build the graph:

```sh
uv tool install graphifyy
graphify update .      # build the graph
graphify hook install  # rebuild it automatically after each commit
```

Then query it instead of reading files at random:

```sh
graphify query "how does the privacy gate enforce redaction?"
graphify explain "PrivacyGate"
graphify affected "ContextSnapshot" --depth 2
```

`graphify-out/` is generated, gitignored, and kept current by a `post-commit`
hook; `graphify-out/GRAPH_REPORT.md` inside it is the architecture summary. See
[`AGENTS.md`](AGENTS.md) for the conventions automated contributors follow.
