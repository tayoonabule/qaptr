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

## Figma design-to-code work

For a full native-UI rebuild, the authoritative Figma root is **Main App**,
node `2:12`. Start from that canvas, not from an individual state such as the
menu bar. The Figma file contains the complete state inventory below that root.

The local `figma-desktop` MCP server is already connected. Do **not** fall back
to browser authentication or ask the user to configure a new integration.
Before the first `get_design_context` request in a session, create and use this
exact approved asset directory:

```sh
mkdir -p /Users/light/Documents/GitHub/qaptr/.jcode/figma-assets
```

Every `figma-desktop.get_design_context` call must include the exact argument:

```json
"dirForAssetWrites": "/Users/light/Documents/GitHub/qaptr/.jcode/figma-assets"
```

This is an approved Figma Dev Mode directory and was verified on 2026-08-27.
Do not substitute the agent sandbox mirror (`/Users/jh/...`), a scratch
directory, Downloads, `artifactDir`, or `artifactPath`: those are rejected by
the desktop MCP. Invoke the raw MCP tool as `get_design_context`, not through a
`toolName` argument. After each successful design-context request, retrieve the
node screenshot as the MCP response requires.

If motion data is needed, call `get_motion_context` on an inspected **frame**,
not the root canvas `2:12`; the desktop MCP intentionally rejects motion
queries for canvases. An empty frame-level motion result means that frame has
no Figma-defined animation, not that MCP access failed.

Follow the `figma-design-to-code` skill phase locks exactly: variables before
metadata, a complete top-down queue before detailed context, vector export
halts, then implementation and screenshot audit. Run the large metadata map on
`2:12` before splitting independent screen branches with Swarm. The current
UI is disposable presentation scaffolding only; preserve behavioral contracts,
privacy guarantees, persistence, integrations, and accessibility semantics.

## Quality gates

Run the same gates as CI before handing work back:

```sh
cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace
cargo doc --workspace --no-deps
```

The Swift packages have their own suites, which the Rust gates above do not
cover:

```sh
swift test --package-path apps/helper
swift test --package-path apps/review
```

## Releases

Merging to `main` with a change to shipped behavior means cutting a release.
`docs/release-process.md` is the procedure: update `CHANGELOG.md`, build and
sign with an incremented `QAPTR_BUILD_VERSION`, install locally, confirm the
installed build has no code diff against the commit being tagged, then push an
annotated `vX.Y.Z` tag.

Two conventions matter more than the rest:

- Build numbers are monotonic and never reused, because a bug report carries the
  build number rather than the commit.
- A green test suite is not an observation of the shipped app. When a changelog
  entry claims a fix works, name what was observed against the installed signed
  build. The env-gated probes
  (`QAPTR_REVIEW_PAINT_FILE`, `QAPTR_REVIEW_SURFACE_FILE`,
  `QAPTR_REVIEW_CONTENT_FILE`) exist so UI states are checkable without a
  visible screen; pair one with a negative control, since a probe that only ever
  emits one value proves nothing.
