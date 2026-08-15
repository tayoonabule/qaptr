# Full product visual redesign plan

## Design read

Qaptr is a privacy-first macOS companion and editorial product site for design-conscious technical users. The direction is quiet editorial utility: off-white paper, charcoal ink, one signal-orange accent, New York-style serif only for page moments, system sans for work, and monospaced data. It should feel deliberate and alive, never dashboard-like or decorative.

- Design variance: 7
- Motion intensity: 6
- Visual density: 4

## Current audit

### Shared failures

1. The website and app do not yet share a reliable spatial system. Margins, rules, control heights, and headline scale are being decided locally.
2. Interactions have been treated as press effects instead of a complete state language. Hover, pressed, selected, keyboard focus, disabled, loading, error, empty, success, and reduced-motion behavior need one contract.
3. Current native views use blank space as a substitute for composition. Space must articulate groups, frame decisions, and give status a location.
4. Native errors expose implementation detail as the visual focal point. Human explanation, recovery action, and diagnostic detail need distinct hierarchy.
5. Default AppKit control chrome must be removed from all user-facing selection paths. Custom controls must preserve VoiceOver labels, selected values, keyboard access, and clear focus after Tab.

### Native app surfaces

#### Window chrome and navigation

- Use one off-white window and content surface with no visible titlebar seam.
- Keep the titlebar to traffic lights plus Qaptr. Move surface switching into each content header as a quiet text action with an explicit accessible label.
- Use a single 40 point desktop gutter and 680 point content measure. Every screen begins from this grid.

#### Observation sheet

- Header: Qaptr in mono and a serif statement that reflects the real state.
- Live capture evidence: one compact asymmetric fact cluster, only when the helper has real values.
- Observation state: title, plain summary, confidence line, and a sparse separator. Rows enter once with a 40 ms cascade.
- Empty state: describe exactly what will make the sheet useful without promising background execution.
- Error state: make recovery the message, expose diagnostics only as subordinate detail, and include an actual retry action.
- Notice state: keep count-only privacy notices quiet and separate from observations.

#### Settings

- Header has a one-sentence purpose and a clear return to observations.
- Capture: real capture state, cadence, display count, and a cache-duration option rail. No popup menu.
- Analysis: always-visible provider radio rows with spring selection, hover wash, keyboard selection, and no network side effect.
- Privacy: request rows explain the permission before the action. The login and capture toggles have an intentional on, off, hover, pressed, focus, and disabled state.
- Exclusions: labels above fields, inline validation below fields, add disabled for blank input, removable entries with no ambiguous action.
- Use rules between meaningful groups, not around every row.

#### Onboarding

- Maintain five real stages and explicit in-flow Back navigation.
- Progress stays a single aligned component with a readable step value and VoiceOver label.
- Every stage uses a different information composition:
  - Permissions: two explained request rows with required and optional hierarchy.
  - Displays: detected count plus a plain statement of the default selection.
  - Capture: two factual principles, one cadence fact and one privacy fact.
  - Provider: radio list with instant local feedback and no request.
  - Privacy: local-redaction and explicit-approval promises as separate statements.
- Back is a compact low-emphasis button. Continue and Finish are a consistent dark primary action.
- Stage movement is directional and reduced-motion aware. Nothing should receive automatic keyboard focus on launch or stage change.

### Website surfaces

#### Home

- Preserve the editorial left-aligned hero and existing content order.
- Use one responsive type scale verified at desktop, tablet, and mobile. No accidental third desktop headline line.
- Keep waitlist form controls on the same visual baseline with identical height and predictable mobile stack.
- Build one real visual narrative around the existing ArcDiagram and product capture imagery. Motion should reveal sequence and causality, not provide ambient decoration.
- Passage sections need deliberate variation through spacing, crop, and content hierarchy rather than local label tricks.

#### Waitlist flow

- Input focus, invalid email, submitting, success, failure, no-JS submission, and keyboard-only flow are all first-class screens.
- Primary actions have clear hover lift, press compression, disabled state, and a stable size across copy changes.
- Thank-you and error pages use the same content measure, header, controls, and motion system as home.

## Interaction contract

1. Nothing receives focus automatically when a window or screen appears. Tab begins focus traversal and shows the native focus ring.
2. Hover changes color or a subtle surface wash within 120 ms. Press scales to 0.97. Selection uses a spring under normal motion and an immediate change under Reduce Motion.
3. No action is visually enabled unless it can run. Blank exclusion fields keep Add disabled. Retry is only shown for a retryable loading failure.
4. Selection controls always expose title, selected state, and value to VoiceOver.
5. Navigation and onboarding transitions are directional and preserve state. Back never causes a provider request or resets permission state.

## Acceptance loop

For each surface, repeat: build, launch, screenshot at window width 560 and 1024, inspect alignment and whitespace, execute keyboard traversal, inspect VoiceOver tree, exercise hover/press/selection and reduced motion, then run automated tests. A screen only passes when its default, empty, error, and selected states all pass.
