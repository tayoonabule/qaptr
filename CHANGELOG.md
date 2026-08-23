# Changelog

All notable changes to Qaptr are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

`Version` is the user-facing `CFBundleShortVersionString`
(`QAPTR_VERSION`). `Build` is the monotonic `CFBundleVersion`
(`QAPTR_BUILD_VERSION`), which increments on every installable build even when
the version is unchanged. Both are recorded because a bug report carries the
build number, not the commit.

Entries state what changed for a user of the app. Where a change was verified
against an installed signed build rather than only by tests, the evidence is
named, because "tests pass" and "the app works" are different claims.

## [Unreleased]

### Changed

- Future changes will be recorded here.

### Added

- Future additions will be recorded here.

## [0.1.1-beta.2] - 2026-08-23 (build 11)

This public Apple-silicon beta is distributed through GitHub Releases as an
ad-hoc signed DMG. Apple Developer signing and notarization are not part of
this beta path. The installer verifies the published checksum when available.

### Fixed

- First-run onboarding now refreshes Screen Recording after returning from
  System Settings instead of remaining stuck on “Not yet requested”. The
  permission helper is restarted only after the previous process releases its
  lock, so the live helper snapshot can reflect the new macOS decision.
- The first-run permission handoff uses a more compact panel with less padding
  and tighter spacing, keeping the required action and its status together on
  smaller displays.

### Evidence

- Review Swift tests passed: 195 tests, 0 failures.
- The fix was built from commit `HEAD` and is included in the signed beta
  package and checksum asset published with this release.

## [0.1.1-beta.1] - 2026-08-23 (build 10)

This public Apple-silicon beta is distributed through GitHub Releases as an
ad-hoc signed DMG. Apple Developer signing and notarization are not part of
this beta path. The installer verifies the published checksum when available.

### Added

- A curl-installable GitHub prerelease bootstrap at
  `scripts/install-beta.sh`.
- Public privacy, security, contribution, and release documentation.
- Honest analysis progress stages for finding captures, protecting content
  locally, and creating observations, including live evidence counts.
- Menu-bar states for local preparation, approval-ready analysis, active
  analysis, completed results, and recovery.

### Changed

- Review surfaces use a quieter glass-backed progress treatment with reduced
  motion support.
- Settings navigation now moves the review surface left and the settings
  surface in from the right, with a slower, softer fade transition.
- The packaged Qaptr app owns the Screen Recording permission boundary through
  its nested helper and reports helper state honestly.

## [0.1.0] - 2026-08-20 (build 9)

First release with a recorded changelog. Earlier work is summarized rather than
itemized, since it predates this file.

### Fixed

- Sandboxed provider CLIs could not complete analysis. The sandbox profile
  denied `com.apple.SecurityServer`, so every HTTPS handshake failed with an
  unknown-issuer error, and denying the whole home subpath hid the home
  directory entry itself, which broke `realpath(3)` for allowed paths beneath
  it. Provider CLIs resolve their state directory on startup and treat that
  failure as fatal. Verified by both allows being byte-present in the shipped
  dylib and by a completed analysis run persisting 12 observations with 0
  failure notices.
- Helper status-menu items could open the review app on the wrong surface. On a
  cold launch the helper posted its distributed notification as soon as the open
  call succeeded, which can precede the app registering its observers, so the
  command was silently dropped. The intent is now also passed as a launch
  argument, which macOS delivers only when it actually spawns a new instance, so
  the warm and cold paths are complementary rather than racing.
- The review header could disagree with the body, reading "What Qaptr found"
  above an empty state, because the three-way render decision was computed twice
  from the same state. Both now derive from one value, so the drift is
  unrepresentable.
- Both navigation rail items were exposed to assistive technology and UI
  automation as untitled buttons distinguishable only by position. A `Label`
  inside a `.plain` button does not reliably surface its text as the button's
  accessibility label, so the controls are now named explicitly.

### Added

- Env-gated instrumentation for states that are otherwise only observable by
  looking at the window, which is impossible while the screen is locked:
  `QAPTR_REVIEW_PAINT_FILE` (first paint), `QAPTR_REVIEW_SURFACE_FILE`
  (resolved surface), and `QAPTR_REVIEW_CONTENT_FILE` (which review body
  rendered). These make acceptance checks scriptable against a real signed
  build. They are inert unless the variable is set.

[Unreleased]: https://github.com/tayoonabule/qaptr/compare/v0.1.1-beta.2...HEAD
[0.1.1-beta.2]: https://github.com/tayoonabule/qaptr/releases/tag/v0.1.1-beta.2
[0.1.1-beta.1]: https://github.com/tayoonabule/qaptr/releases/tag/v0.1.1-beta.1
[0.1.0]: https://github.com/tayoonabule/qaptr/releases/tag/v0.1.0
