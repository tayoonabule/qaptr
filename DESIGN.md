# Qaptr Native Design System

> Locked from the studied Micro live-site DNA. This document governs the native macOS review app only.

## Direction

Qaptr is a quiet review instrument, not a dashboard. The post-onboarding shell uses a persistent left rail, one compact Azure-to-Teal masthead, and a wide warm-paper work plane. Review data is presented as rows and a status ledger. Do not stack dashboard cards or introduce decorative illustrations.

## Palette

| Token | Value | Role |
|---|---|---|
| `canvasWhite` | `#FBF8F1` | warm paper window and work plane |
| `paperMist` | `#F3EEE2` | quiet rail and secondary paper |
| `ash` | `#E2DDD1` | hairlines and ledger rules |
| `smoke` | `#C9C3B7` | stronger borders |
| `midnightInk` | `#122B35` | primary ink and high-emphasis controls |
| `charcoal` | `#1D3842` | headings and body emphasis |
| `steel` | `#5E7276` | supporting copy |
| `fog` | `#7B8A8B` | metadata and muted labels |
| `electricBlue` | `#1B77F2` | Azure anchor, active state, masthead start |
| `teal` | `#009E9A` | Teal masthead end, live state |
| `softMint` | `#D7F0E8` | high-confidence support fill |

The Azure-to-Teal gradient is reserved for the compact masthead rule and small system signal. It must not become a general-purpose decoration or button fill.

## Typography

- **Editorial display:** native macOS system serif via `Font.system(design: .serif)`, roman, regular weight. Use for the main work-plane title only.
- **UI sans:** native system default via `Font.system(design: .default)`. Use for controls, body copy, and compatibility headline roles.
- **Metadata mono:** native monospaced system design. Use for labels, status values, IDs, and provenance.
- Display is restrained. Avoid oversized marketing headlines, italic headings, and all-caps copy outside metadata labels.

## Structure

- Root gating remains: onboarding is the only pre-completion surface.
- After onboarding, `ContentView` owns a persistent rail with Review and Settings navigation.
- The main plane owns the masthead and uses a row-based observation ledger.
- Status, capture progress, review history, notices, error, empty, refresh, and detail-sheet behavior remain real and data-driven.
- Cards remain a compatibility component for other native surfaces, but the Review plane itself does not use stacked cards.

## Spacing and shape

- 4pt base scale, with 8/12/16/24/32/48pt steps.
- Hairline rules carry structure more often than shadows.
- Controls retain the existing rounded native treatment for compatibility. Review rows use square ledger boundaries and generous horizontal breathing room.

## Motion and accessibility

- Use the existing `QaptrMotion` curves and respect Reduce Motion.
- Animate only opacity and small row translation. Never animate layout or data changes.
- Keep visible focus, semantic labels, and text selection in the detail sheet.

## Compatibility contract

`QaptrHex`, `Color` compatibility names, `QaptrRadius`, `QaptrSpace`, `QaptrType.display/headline/title/body/caption/meta`, `QaptrMotion`, and `QaptrCard` remain available because other native SwiftUI surfaces consume them. New visual code should prefer `QaptrType.editorial`, `Color.qaptrTeal`, and the warm-paper tokens.
