# Figma Main App state matrix

Authoritative root: `Main App` canvas `2:12` in Qaptr Figma file. All primary review frames are 845 x 737 points. The menu-bar board is 400 x 480 and the toast specification board is 560 x 360.

## Traversal inventory

| Area | Figma roots | Implemented native surface |
|---|---|---|
| Onboarding | `10:22` screen-recording permission, `27:1034` not yet requested, `27:1069` denied | `WelcomeView` with permission-driven copy, CTA, privacy footer, and system-settings recovery |
| Home | `13:22` empty, `13:46` findings, `13:93` paused, `13:140` attention, `13:194` analyzing, `11:113` ready, `11:137` quiet result, `11:183` context nudge, `65:110` watching closely, `65:164` done watching | `WorkflowSuggestionsView` / `HomeReviewView`, status toolbar, findings feed, banners, detailed-capture actions |
| Consent | `29:6533` review, `29:6593` choose provider | `ConsentReviewView`, provider selection, explicit approve/decline boundary |
| Finding detail | `34:248` complete, `36:141` incomplete, `36:175` correction, `65:225` saved | `FindingDetailView`, suggestion/correction/save actions and honest unavailable messaging |
| Settings | `29:6787` baseline, `61:107` never-capture sheet | `SettingsView`, capture/privacy/provider sections, exclusion editor |
| Menu bar | `66:128` capturing, `66:151` attention, `66:174` detailed, `66:197` approval | `QaptrMenuBarView` with state-specific status and actions |
| Transient feedback | `66:220` toast spec | `ReviewToastView`, bottom-center placement, three-second dismissal |

## Token bindings

Figma variables were resolved before metadata/context inspection. Native code binds repeated values through the existing Qaptr design tokens and the Figma-derived constants: SF Pro global body sizing, 24-point control height, 16-point button horizontal padding, 6-point button radius, blue/orange/red accents, vibrant secondary fill, primary label, and liquid-glass opacity/dispersion/depth behavior. Existing font and logo resources remain authoritative vector boundaries.

## Visual evidence

- Figma metadata map captured from `2:12`.
- Figma design context and screenshot captured for `11:113` (ready-to-analyze root) at 845 x 737.
- Swift review package tests: 196 tests passed.
- Remaining acceptance work is the installed-app screenshot pass across every state. The repository exposes `QAPTR_REVIEW_PAINT_FILE`, `QAPTR_REVIEW_SURFACE_FILE`, and `QAPTR_REVIEW_CONTENT_FILE` probes for repeatable runtime checks; these probes do not substitute for pixel comparison.
