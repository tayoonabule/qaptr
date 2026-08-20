# Release process

Qaptr cuts a release on every merge to `main` that changes shipped behavior. A
merge that only touches docs, tests, or CI does not need one.

The goal is that any build a user can install maps to exactly one commit, and
that the commit's claims were checked against that build rather than only
against the test suite.

## Version and build numbers

| Field | Variable | Meaning |
|---|---|---|
| `CFBundleShortVersionString` | `QAPTR_VERSION` | User-facing version, semver. Defaults to `[workspace.package].version` in `Cargo.toml`. |
| `CFBundleVersion` | `QAPTR_BUILD_VERSION` | Monotonic integer. Increments on **every** installable build, even when the version does not change. |

Build numbers never repeat or go backwards, because a bug report carries the
build number rather than the commit. Bump the version for user-visible change;
bump only the build for a rebuild of the same behavior.

The version has one source: `[workspace.package].version` in the workspace
`Cargo.toml`. `packaging/release.sh` reads it from there, so there is no second
copy to drift. An explicit `QAPTR_VERSION` still overrides it for a one-off
build, and the script fails loudly if the manifest section is missing rather
than falling back to a stale default.

`release.sh` also asserts that the version and build it resolved match every
nested bundle's `Info.plist` before it will sign, so a mismatch fails the build
instead of shipping.

## Steps

Run the quality gates first. A release from a tree that has not passed them is
not a release.

```sh
cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace
cargo doc --workspace --no-deps
swift test --package-path apps/helper
swift test --package-path apps/review
```

1. **Update `CHANGELOG.md`.** Move `Unreleased` entries under a new
   `## [x.y.z] - YYYY-MM-DD (build N)` heading, and update the link
   definitions at the bottom. Describe what changed for a user, and name the
   evidence where a claim was checked against a signed build.

2. **Build and sign.**

   ```sh
   QAPTR_SIGNING_IDENTITY="Apple Development: <identity>" \
   QAPTR_BUILD_VERSION=N \
   QAPTR_SKIP_REPRODUCIBILITY=1 \
   ./packaging/release.sh
   ```

   Drop `QAPTR_SKIP_REPRODUCIBILITY` to also run the clean-checkout
   reproducibility comparison. A distributed release additionally needs
   `QAPTR_NOTARY_PROFILE` on a release machine; without it the script reports
   the notarization and Gatekeeper steps as blocked rather than passing them.

3. **Install locally and verify against the real build.** Replace the installed
   app rather than merging into it, so no stale nested bundle survives.

   ```sh
   pkill -f Qaptr; pkill -f QaptrHelper; pkill -f QaptrReview
   rm -rf /Applications/Qaptr.app
   cp -R packaging/.build/Qaptr.app /Applications/
   ```

   Confirm the install is the build you just made, and that it corresponds to
   the commit you are tagging:

   ```sh
   defaults read /Applications/Qaptr.app/Contents/Info.plist CFBundleVersion
   codesign -dvvv /Applications/Qaptr.app 2>&1 | grep '^Authority'
   git diff --name-only <tag-or-commit> HEAD -- '*.rs' 'crates/**' '*.swift'
   ```

   An empty diff is what lets the release's acceptance evidence apply to the
   installed build. If the diff is non-empty, the evidence describes different
   code.

4. **Tag the commit.** Annotated tags only, so the tag carries a message and a
   date.

   ```sh
   git tag -a v0.1.0 -m 'Qaptr 0.1.0 (build 9)'
   git push origin main
   git push origin v0.1.0
   ```

5. **Publish the GitHub Release.** The changelog links to
   `releases/tag/vX.Y.Z`, and a git tag alone does not create that page, so
   skipping this leaves a dead link. `--verify-tag` refuses to invent a tag
   that was never pushed.

   ```sh
   gh release create v0.1.0 --verify-tag \
     --title 'Qaptr 0.1.0 (build 9)' \
     --notes "$(sed -n '/## \[0.1.0\]/,/^## \[/p' CHANGELOG.md)"
   ```

   The repository is private, so these URLs 404 for anonymous requests even
   when correct. Check with `gh release view` rather than `curl`.

6. **Record acceptance evidence.** Note in the changelog entry what was
   actually observed, not what was expected. The env-gated probes make UI
   states checkable without a visible screen:

   | Variable | Records |
   |---|---|
   | `QAPTR_REVIEW_PAINT_FILE` | First-paint timestamp |
   | `QAPTR_REVIEW_SURFACE_FILE` | Resolved surface (`review`, `settings`) |
   | `QAPTR_REVIEW_CONTENT_FILE` | Review body (`error`, `empty`, `observations`) |

   These are inert unless set. When using one as evidence, also record a
   negative control: a probe that only ever emits one value proves nothing.

## Evidence standard

`docs/release.md` holds the longer-form evidence log. Keep the distinction it
draws: locally verified components do not override blocked gates, and a green
test suite is not an observation of the shipped app.
