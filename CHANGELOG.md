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

Nothing yet.

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

[Unreleased]: https://github.com/tayoonabule/qaptr/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/tayoonabule/qaptr/releases/tag/v0.1.0
