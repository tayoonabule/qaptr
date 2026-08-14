# Working in this repository

Qaptr is a Rust workspace with a Swift helper app, a small web surface, and
packaging scripts. Read this file before exploring the tree by hand.

## Knowledge graph first

The repository is indexed as a knowledge graph in `graphify-out/`. Query the
graph before grepping or reading files; it answers structural questions in a
fraction of the tokens and returns `file:line` provenance for every edge.

```sh
graphify query "how does the privacy gate enforce redaction?"  # scoped subgraph
graphify explain "PrivacyGate"                                  # one symbol + neighbors
graphify path "AnalysisRunner" "Vault"                          # how two things connect
graphify affected "ContextSnapshot" --depth 2                   # blast radius before editing
graphify god-nodes --top 10                                     # architectural hubs
graphify update .                                               # rebuild after code changes
```

Rules:

- Any question about where something lives, what calls what, or what a change
  breaks starts with `graphify query` / `explain` / `path` / `affected`.
- Run `graphify affected "<symbol>"` before changing a shared type. The hubs
  (`ProviderError`, `CliRuntimeError`, `Vault`, `CredentialKey`, `CliOutput`,
  `ContextSnapshot`) ripple across crates.
- Read `graphify-out/GRAPH_REPORT.md` for architecture review, not for
  targeted lookups.
- Fall back to `rg` only when the graph misses (string literals, config values,
  comments, or files the extractor skipped).
- Run `graphify update .` after editing code. It is AST-only, takes a few
  seconds, and costs nothing. A `post-commit` hook also rebuilds in the
  background.

`graphify-out/` is generated and gitignored, so every contributor builds it
locally:

```sh
uv tool install graphifyy   # once
graphify update .           # in the repo root
graphify hook install       # git hooks are not cloned; install them per checkout
```

## Parallel agents

When several agents work on this repository at once, the graph is the shared
map. Each agent should:

1. Build or refresh its own local graph before starting (`graphify update .`).
2. Scope its slice with `graphify query` and confirm the blast radius with
   `graphify affected` before editing, so two agents do not collide on the same
   hub type.
3. Re-run `graphify update .` after its edits, and re-check `affected` for any
   shared symbol it touched before handing work back.
4. Cite `file:line` from graph output when reporting findings, so a reviewer
   can audit the path rather than re-deriving it.

`graphify-out/` is gitignored precisely so parallel workers never conflict on a
large generated file. Each one rebuilds it in seconds.

## Quality gates

Run the same gates as CI before handing work back:

```sh
cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace
cargo doc --workspace --no-deps
```

The Swift helper has its own suite: `swift test --package-path apps/helper`.
