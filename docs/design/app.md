# Review app design rationale (U20)

This records the design decisions for the opened review app before treating
the implementation as final, matching the discipline `docs/design/website.md`
already established for U21.

## Benchmark and constraints

The design brief is explicit and non-negotiable: Apple and Linear restraint,
system-aware appearance, mostly-white or mostly-black, no card grids, no
gradients, no glassmorphism, no decorative icons. Simplicity is Granola-level:
opening Qaptr shows a few useful observations, not a dashboard (R-D2, R-D3).

## What was built

### Observation Sheet (primary surface)

A single scrollable column, max width 640pt, left-aligned. No card
background, no border, no shadow, no grid. Each observation is a plain
title/summary/confidence stack separated by a hairline `Divider()` — the same
compositional move as shopify.design's hairline rules, applied here instead of
a card boundary. Confidence is rendered as a plain monospaced label
(`Low confidence` / `Moderate confidence` / `High confidence`) derived
directly from the measured score via `ConfidenceBand`, never rounded up and
never invented when a score is missing.

Empty, error, and quiet-exclusion states are plain text blocks with no
illustration, no icon, and no call-to-action that could be mistaken for
launching something. This matches R-D5's requirement that every state
receives deliberate attention without escalating visual weight beyond the
Observation Sheet's own restraint.

### Settings

Exactly the six things R-D6 allows: the bounded capture interval (5 seconds
through 5 minutes, adjustable in 5-second steps and applied by the helper on
its next poll), displays (count, informational; the full multi-display picker
is U7's captured-selection surface), cache duration, provider,
privacy/permission status, and the two exclusion lists (applications, window
titles) that make the privacy posture legible and adjustable, per this unit's
explicit requirement. No other capture control exists. Sections are separated by
uppercase monospaced labels (mirroring the "voice vs. report" typographic
contrast documented in U21's design rationale) rather than boxed cards.

### Onboarding

Five stages matching R-D7 exactly: permissions, displays, capture
explanation, provider selection, privacy consent. Screen Recording and the
optional Accessibility context permission are explained and requested
separately, satisfying AE9. No provider request occurs before the final
privacy-consent stage is reached, matching KTD10's just-in-time consent
boundary — onboarding's provider-selection stage only records a local
preference; it does not invoke `qaptr-provider-cli` or `qaptr-provider-openrouter`.
Onboarding runs at most once per installation, tracked by
`SettingsPreferences.onboardingCompleted`, so it never re-appears and never
nags.

## What was deliberately not built

- **No dashboard, no widgets, no charts.** A single vertical list is the
  entire information architecture of the primary surface.
- **No sidebar navigation.** A single toolbar button toggles between the
  Observation Sheet and Settings, avoiding a persistent chrome affordance that
  would read as a productivity app rather than a note.
- **No decorative iconography anywhere.** Every visual element is typography,
  a hairline divider, or a plain system control (`Picker`, `Toggle`,
  `TextField`, `Button`). No SF Symbol or custom glyph is used as decoration.
- **No color beyond system semantic colors.** `Color(nsColor: .textBackgroundColor)`
  and SwiftUI's `.secondary`/`.tertiary` foreground styles are the entire
  palette, so light and dark appearance follow the system automatically
  without a bespoke light/dark branch.
- **No action that executes anything.** Every button in this unit either
  reads state, writes a local preference, requests a permission, or advances
  an onboarding stage. None launches a tool, invokes a provider, or starts an
  automation, matching the product line's explicit constraint that Qaptr
  describes work and never performs it.

## Scope risk and what remains open

- **Full production-session memory measurement remains a follow-up.**
  `bench/review_memory.md` records a real, measured smoke number (26.845 MiB
  median / 28.017 MiB peak against a 150/180 MiB budget) for the opened app
  idling on an empty durable-history database, not the plan's full 24-capture
  scripted session. That full assertion is U23's release-validation
  responsibility once the fixture session exists.
- **Keyboard traversal and VoiceOver were exercised manually, not by an
  automated accessibility test.** SwiftUI's native controls (`Picker`,
  `TextField`, `Button`, `Toggle`) inherit standard focus-ring and VoiceOver
  behavior for free. The custom-drawn provider rows, cache-lifetime rail, and
  onboarding permission/provider rows are hand-labeled with explicit
  `accessibilityLabel`/`accessibilityValue` pairs so VoiceOver announces the
  same selected/not-selected state a sighted person sees, but this remains a
  manual/unit-tested guarantee rather than an automated UI-accessibility
  audit.
- **Reduced-motion is respected for the one animated transition** (the
  Observations/Settings toggle) by checking
  `accessibilityReduceMotion` and skipping `withAnimation` entirely when it is
  set. There is no other motion in this unit to gate.
- **The capture interval is intentionally scalar.** The review app writes only
  the bounded interval control file. The helper polls it and applies a valid
  change on its next poll; it never receives image contents through this UI.
