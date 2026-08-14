# U3 shell measurement gate

**Date:** 2026-08-14 UTC
**Decision:** proceed with **native SwiftUI** for the opened review shell.
**Rejected:** Tauri 2 for the v1 opened shell.
**Confidence:** medium. The probe evidence is strong for shell startup, identity shape, and idle memory, but it is not a production review-session measurement.

## Gate and scope

U3 decides whether KTD3 and assumptions A2/A5 hold before the review app is built out. The probes are intentionally disposable. They render only a small Observation Sheet-like window and do not contain review logic, storage, capture, privacy, providers, or the Rust core.

The plan defines opened-app memory as the sum of `phys_footprint` across the process tree, sampled once per second. The plan's full opened-app protocol is a 10-minute scripted review session with a 24-capture fixture. That fixture and review flow do not exist yet, so this spike measured the requested smallest possible trivial window instead: three 20-second runs per candidate, plus one 120-second idle run per candidate. Every sample still used `footprint -f bytes` and summed the root process and all descendants. The short probe scope is a limitation, not an estimate of production behavior.

Reference machine:

- MacBook Air Mac17,4, Apple M5, 24 GB RAM, arm64
- macOS 27.0, build 26A5388g
- Built-in Color LCD, 2880 x 1864 Retina
- Xcode 26.6, Swift 6.3.3, Rust 1.97.1, Tauri CLI 2.8.4, resolved Tauri crate 2.11.5

## Measurements

All numbers below are measurements from this machine. Memory is MiB converted from the byte values emitted by `footprint`. Each run sampled once per second for 20 seconds, with 19 successful samples because process startup/teardown was outside the fixed sampling window. `run median` and `run peak` are over that run's samples. The summary median is the median of the three run medians; summary peak is the greatest observed run peak.

| Shell | Run | First meaningful paint | `phys_footprint` median | `phys_footprint` peak |
|---|---:|---:|---:|---:|
| SwiftUI | 1 | 154.6 ms | 25.45 MiB | 25.77 MiB |
| SwiftUI | 2 | 207.0 ms | 26.31 MiB | 26.52 MiB |
| SwiftUI | 3 | 197.5 ms | 25.75 MiB | 26.44 MiB |
| **SwiftUI summary** |  | **197.5 ms median** | **25.75 MiB** | **26.52 MiB** |
| Tauri 2 | 1 | 667.0 ms | 26.36 MiB | 26.69 MiB |
| Tauri 2 | 2 | 304.9 ms | 25.22 MiB | 26.70 MiB |
| Tauri 2 | 3 | 328.8 ms | 23.80 MiB | 26.72 MiB |
| **Tauri 2 summary** |  | **328.8 ms median** | **25.22 MiB** | **26.72 MiB** |

The additional 120-second idle runs were also sampled once per second:

- SwiftUI: first paint 150.1 ms, median 25.36 MiB, peak 26.53 MiB.
- Tauri 2: first paint 308.2 ms, median 25.22 MiB, peak 26.52 MiB.

Both trivial probes are below the 150 MiB opened-app median and 180 MiB peak budgets by a wide margin. This does **not** prove the production review flow meets those budgets because neither probe loaded the planned 24-capture fixture or performed analysis, observation opening, workflow generation, or four exports.

## Identity and signing shape

Both probes were arm64 app bundles and were ad hoc signed because no Developer ID certificate was available for this spike. Neither has a TeamIdentifier. This is a real signing-shape observation, not a production signing result.

| Shell | Bundle identifier | Executable | Code-signing shape |
|---|---|---|---|
| SwiftUI | `com.qaptr.u3.swiftui` | `QaptrSwiftUIShell` | ad hoc, arm64, sealed resources, no TeamIdentifier; changed-build CDHash `0542aa4ac730ed47d31c2499460a73b952870c8ade3388a1006f75dbc7270fc9` |
| Tauri 2 | `com.qaptr.u3.tauri` in the app `Info.plist` | `qaptr-tauri-shell-probe` | ad hoc linker-signed debug bundle, no TeamIdentifier, `Info.plist=not bound`, no sealed resources; final changed-build CDHash `9c8deeead2cadf1ff663dd71eaa4dacc857e64c67d27fb447b07f5936fe72325` |

The Tauri executable's code-directory identifier was `qaptr_tauri_shell_probe-97389b05dcb38242`, while the bundle `Info.plist` identifier was `com.qaptr.u3.tauri`. That mismatch is acceptable as a disposable debug bundle observation, but it is a less clean starting shape for the stable nested signed app in KTD3/KTD13. `codesign --verify --deep --strict` also rejected this debug bundle because it had no resources while its signature indicated resources should be present. The production candidate would need a real Developer ID signing pass and a nested-bundle verification before release.

## Screen Recording TCC persistence

Each candidate was tested with its own stable bundle identifier. The sequence was:

1. `tccutil reset ScreenCapture <bundle-id>`.
2. Launch the probe with its real `CGRequestScreenCaptureAccess` path enabled.
3. Terminate and relaunch without requesting permission.
4. Rebuild the probe with a changed code hash and relaunch without requesting permission.

Observed records:

- SwiftUI request launch: `before=1 requested=1 after=1`.
- SwiftUI same-build restart: `before=1 requested=0 after=1`.
- SwiftUI changed-build rebuild, new CDHash above: `before=1 requested=0 after=1`.
- Tauri request launch: `before=1 requested=1 after=1`.
- Tauri same-build restart: `before=1 requested=0 after=1`.
- Tauri changed-build rebuild, new CDHash above: `before=1 requested=0 after=1`.

The authorized state persisted across restarts and across changed ad hoc rebuilds for both candidates. A limitation is important: after the explicit `tccutil reset`, `CGPreflightScreenCaptureAccess()` still returned `true` on this machine before either request. Therefore this spike could not observe a not-determined-to-granted transition or prove fresh-user prompt UX. It did observe the persistence question that is actionable for shell selection. A fresh macOS user or a clean TCC database is still required before shipping onboarding.

## Decision

Choose **native SwiftUI** and reject Tauri 2 for the opened shell in v1.

Reasons:

1. SwiftUI had the faster measured first meaningful paint: 197.5 ms median versus Tauri's 328.8 ms median.
2. Both shells passed the trivial-window memory gate by a large margin. Tauri's median was 0.53 MiB lower, but SwiftUI's worst observed peak was 0.20 MiB lower. The difference is noise-level relative to the 150/180 MiB budgets, so memory does not justify carrying WebKit and a second signing shape.
3. TCC behavior was equivalent in the measurable direct-launch state. It does not rescue Tauri from its slower launch or weaker disposable signing shape.
4. SwiftUI is the native path intended by the architecture principles for the macOS surface and removes the webview dependency from the opened shell. The Rust core, storage, privacy, capture, and provider boundaries remain unchanged.

This decision supersedes KTD3's provisional Tauri choice for the review shell. It does not change KTD1's native Swift capture-helper decision or any domain architecture.

## What would overturn the decision

Re-open the choice only after both production-shaped candidates run the plan's full 10-minute script with the committed 24-capture fixture and real typography/motion:

- SwiftUI exceeds 150 MiB median or 180 MiB peak, or cannot meet keyboard traversal, appearance, and review-surface quality without a materially larger implementation risk.
- Tauri, rebuilt as a properly Developer ID-signed nested app with the bundle identifier and code requirement fixed, demonstrates a materially better production cold paint and equal-or-better process-tree memory while preserving Screen Recording consent across restart and rebuild on a clean user profile.
- A clean-profile TCC test shows a shell-specific persistence or signing failure that the current authorized-state test could not expose.

Until that evidence exists, production review UI work must proceed with SwiftUI and the Rust core untouched by this shell decision. The probe sources remain under `bench/probes/` and their generated bundles are ignored as disposable artifacts.
