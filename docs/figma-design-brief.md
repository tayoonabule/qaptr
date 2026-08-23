# Qaptr Figma Design Brief

> A screen-by-screen source of truth for designing Qaptr's native macOS beta in Figma.
>
> This document is intentionally implementation-aware. It gives a designer the product states, exact copy, representative data, action labels, and privacy boundaries needed to create a complete design file without inventing behavior.

## 1. Product frame

Qaptr is a quiet, privacy-first work journal for macOS. It takes occasional, downscaled screenshots locally, keeps them in a local vault, and turns selected moments into review observations or workflow candidates only after an explicit analysis consent.

### Core promises

- Capture is occasional, never continuous recording.
- Capture stays local until the person starts and approves an analysis session.
- Screen Recording is required for capture and is owned by `QaptrHelper`.
- Accessibility context is optional. It adds frontmost app and window-title context but is not required for capture.
- Provider credentials remain owned by the provider CLI or the Mac Keychain. Qaptr does not ask for API keys for local CLI providers.
- Every provider analysis session has a fresh consent step.
- UI copy must state observed facts, not optimistic assumptions.

### Primary product surfaces

1. First-run onboarding.
2. Returning review workspace.
3. Workflow candidate understanding/detail.
4. Analysis consent sheet.
5. Observation list and observation detail sheet.
6. Settings.
7. Provider setup sheet.
8. Menu-bar companion.

## 2. Figma file structure

Create these Figma pages or sections:

- `00 — Cover + principles`
- `01 — Foundations`
- `02 — First run`
- `03 — Review workspace`
- `04 — Workflow understanding`
- `05 — Analysis consent + progress`
- `06 — Settings`
- `07 — Provider setup`
- `08 — Menu bar`
- `09 — Components`
- `10 — State matrix + prototype map`

For each primary screen, create:

- Default light appearance.
- Narrow window variant.
- Loading, empty, success, warning, and error states where listed.
- Reduce Motion variant for transitions.
- Keyboard focus and disabled states for interactive controls.
- At least one long-copy stress variant.

## 3. Foundations

### Recommended frame sizes

| Surface | Primary frame | Narrow frame | Notes |
|---|---:|---:|---|
| Onboarding | 1040 × 720 | 820 × 600 | Resizable macOS window. Keep the required action visible without scrolling. |
| Review workspace | 1100 × 760 | 820 × 600 | One adaptive canvas, no permanent navigation rail. |
| Workflow detail | 1100 × 800 | 820 × 600 | Long content scrolls vertically. |
| Settings | 1040 × 760 | 820 × 600 | Grouped native settings form, max content width about 620. |
| Provider sheet | 460 × 360 | 420 × 360 | Focused modal sheet. |
| Observation detail | 620 × 420 | 520 × 460 | Sheet, no source screenshot thumbnails. |
| Analysis consent | 620 × 520 | 520 × 600 | Non-dismissible while consent is pending. |
| Menu bar | 320 × 420 | n/a | Native status-item menu, compact rows. |

### Visual direction

- Native macOS utility, editorial but restrained.
- Warm white canvas, quiet translucent material, thin hairlines, dark blue-green ink.
- One blue accent for primary actions and selected state.
- Teal or green for confirmed/live states.
- Tangerine for permission or recovery warnings.
- Red only for errors or destructive consequences.
- Avoid gradients, decorative aurora backgrounds, card grids, oversized empty typography, excessive pills, fake window chrome, and card-in-card nesting.
- Use SF Symbols for status and action icons.
- Use a continuous ranked list for workflow candidates. Do not use three equal feature cards.

### Tokens

| Token | Value / direction |
|---|---|
| Canvas | `#F8FAFB` warm white |
| Raised mist | `#EEF3F5` |
| Hairline | `#D9E3E7` |
| Primary ink | `#1D3842` |
| Soft ink | `#5E7276` |
| Muted ink | `#7B8A8B` |
| Accent | Electric blue, approximately `#1B77F2` |
| Accent strong | Deep sapphire, approximately `#0E55BB` |
| Success | Vivid green, approximately `#0B8F7A` |
| Warning | Tangerine, approximately `#D96B38` |
| Error | `#B42318` |
| Spacing | 4, 6, 10, 14, 20, 28, 40, 56 px |
| Radius | 6 input, 8 control, 12 card, 16 feature |
| Motion | 100–300 ms. Reduce Motion uses crossfade/no travel. |

### Accessibility requirements

- Every icon has a text label or is decorative and hidden from VoiceOver.
- Status colors are always paired with text.
- Keyboard focus must be visible after Tab, but not preselected on first launch.
- Primary actions use a clear default-button treatment.
- Do not encode “granted”, “warning”, or “error” by color alone.

## 4. First-run onboarding

The first-run flow is a short permission handoff, not a marketing tour. Use one calm panel, a two-step progress indicator, and one dominant action.

### Screen F1 — Screen Recording not yet requested

**Route:** `firstRun / screenRecording`

**Header**

- Brand: Qaptr logo + `Qaptr`
- Eyebrow: `FIRST RUN`
- Title: `Capture your work, quietly.`
- Statement: `Qaptr takes an occasional screenshot on this Mac so you can review patterns later. Capture stays local until you choose an analysis session.`

**Progress**

- `STEP 1 / 2`
- First segment blue, second segment hairline.

**Body**

- Heading: `Allow Screen Recording`
- Explanation: `Screen Recording is the one required permission. QaptrHelper owns capture and reports the live result here.`
- Status row:
  - Icon: dashed circle / warning tint.
  - Label: `Not yet requested`
  - Detail: `Qaptr needs Screen Recording to take an occasional, downscaled screenshot every few minutes. It never records continuously and never uploads a screenshot until you choose to review it.`
- Primary button: `Allow Screen Recording`
- Footer: shield icon + `You can change privacy and capture choices later in Settings.`

**Interaction**

Clicking the primary button opens macOS Privacy & Security → Screen Recording and starts the helper permission handoff. The screen polls for live helper state. It must not remain stuck at the initial state after the user returns.

### Screen F2 — Screen Recording needs permission

Same layout as F1, but:

- Status label: `Needs permission`
- Status icon: warning circle.
- Primary button: `Open System Settings`
- Add small recovery copy: `Enable QaptrHelper in Screen Recording, then return to Qaptr.`

### Screen F3 — Screen Recording granted

Same layout, but:

- Status icon: filled checkmark circle in success green.
- Status label: `Granted`
- Supporting line: `When you finish this step, capture starts immediately. There is no separate start screen.`
- Primary button: `Continue`

Transition to F4 should be a calm right-to-left handoff. Reduce Motion uses a crossfade.

### Screen F4 — Optional context

**Progress:** `STEP 2 / 2`, both segments active.

- Heading: `Add optional context`
- Explanation: `Optional: allow Qaptr to read the frontmost app and window title. This adds context, but capture does not depend on it.`
- Status row title: `App and window names`
- Status values:
  - `Not yet requested`
  - `Needs permission`
  - `Granted`
- Secondary button: `Allow optional context`
- Primary button: `Start capture`
- Quiet alternative: `Start without optional context`
- If no display is available: warning `Connect at least one display before capture can begin.`
- If completion fails: `Qaptr could not finish setup yet. Check the live permission and helper status, then try again.`

### Onboarding state data

```json
{
  "screenRecording": "notDetermined | denied | granted | unavailable",
  "accessibilityContext": "notDetermined | denied | granted | unavailable",
  "availableDisplays": 1,
  "selectedDisplays": ["main-display"],
  "intervalSeconds": 30,
  "onboardingCompleted": false
}
```

## 5. Returning review workspace

The post-onboarding app is one adaptive canvas. Settings is a separate destination reached by a small action, not a permanent rail.

### Shared top status area

Every returning workspace state may show:

- Qaptr wordmark or compact title.
- Capture status: `Capture on`, `Capture paused`, or `Capture needs attention`.
- Last capture: `Last capture 2 minutes ago`.
- Settings action.

### Screen R1 — Loading

- Header: `Review`
- Body: quiet spinner or progress indicator.
- Copy: `Loading your local review history.`
- No provider call, no network language, no fake count.

### Screen R2 — No captures

- Header: `Review`
- Copy: `Qaptr has not captured anything yet.`
- Detail: `When the helper makes its first local capture, it will appear here.`
- Status: `Capture on` or truthful recovery state.
- Action: `Open Settings`
- Optional detail: configured cadence, e.g. `Every 30 seconds`.

### Screen R3 — Capture unavailable

- Header: `Review setup`
- Warning title: `Capture status unavailable`
- Detail: `Qaptr cannot confirm the helper's current state.`
- Action: `Try again`
- Secondary action: `Open Settings`

### Screen R4 — Capture permission required

- Warning title: `Capture permission needed`
- Detail: `Grant Screen Recording permission to continue.`
- Action: `Review privacy`
- Icon: lock shield / warning.

### Screen R5 — Provider setup needed

- Header: `Review`
- Title: `Connect a provider to analyze captures`
- Detail: `Your captures are local. Choose a supported provider in Settings when you are ready to create observations.`
- Action: `Open Settings`
- Privacy note: `Nothing is sent by choosing a provider. Qaptr asks separately before each analysis session.`

### Screen R6 — Ready to analyze

- Header: `Review`
- Title: `Turn captures into observations`
- Detail example: `18 screenshots available. Preparation stays on this Mac.`
- Primary action: `Analyze captures`
- Small privacy line: `Qaptr will prepare and redact content locally before asking for consent.`

### Screen R7 — Analysis working

Use a single progress module with factual stages:

1. `Finding screenshots in your local vault`
   - `Qaptr is opening committed captures. Nothing has left this Mac.`
2. `Protecting screenshots on this Mac`
   - `OCR is extracting text while privacy rules remove sensitive content before approval.`
3. `Ready for your approval`
   - `Review exactly what will be sent before the provider is invoked.`
4. `Claude CLI is reviewing approved text` or provider-specific equivalent.

Actions:

- During work: `Cancel`
- After failure: `Try again`
- Never display a fake percentage unless the model supplies one.

### Screen R8 — Consent required

The main surface behind the sheet should show:

- Title: `Ready for your approval`
- Detail: `Review exactly what will be sent before the provider is invoked.`
- Status label: `CONSENT REQUIRED`

Open the consent sheet described in Section 7.

### Screen R9 — Candidates ready

Header: `What Qaptr found`

Subhead: `A calm record of what Qaptr has observed. Capture and analysis stay separate.`

Show one continuous ranked list with 3 candidates. Candidate 1 has slightly more vertical emphasis. Each row includes:

- Rank: `01`, `02`, `03`
- Title
- Plain-language rationale
- Evidence status
- Confidence basis or capture count
- Observed time span
- Action: `Understand this workflow`

### Screen R10 — Insufficient evidence

Use one of these honest variants:

- `Not enough evidence yet`
- `No privacy-safe capture content was eligible for this analysis.`
- `The request stayed local because provider consent was declined.`
- `Analysis completed without a supported workflow candidate result.`

If a recommendation exists, show:

- `Capture more detail`
- `Every 15 seconds for 30 minutes`
- Action: `Review detailed capture`

### Screen R11 — Evidence without candidates

- Title: `Observations are ready`
- Detail: `Qaptr wrote 5 observations, but did not produce a supported workflow candidate.`
- Action: `View observations`
- Secondary: `Analyze again`

### Screen R12 — Analysis failed

- Header: `Review setup`
- Title: `Analysis needs attention`
- Detail from model, example: `The selected provider could not complete the review.`
- Action: `Try again`
- Secondary: `Open Settings`

### Screen R13 — Analysis cancelled

- Title: `Analysis cancelled`
- Detail: `No provider result was saved.`
- Action: `Analyze captures`

## 6. Workflow understanding surface

This surface is the destination after selecting a candidate. It may be a pushed detail view or a full-canvas state.

### Workflow detail — enough information

- Breadcrumb/back: `Back to review`
- Rank/status: `01 · Enough information`
- Title: `Validate a product change before release`
- Summary: `Qaptr repeatedly saw implementation, review feedback, and a packaged-build check in the same work period.`
- Evidence block:
  - `8 captures`
  - `42 minutes observed`
  - `High confidence`
  - Basis: `8 captures across 42 minutes showed the same implementation-to-verification sequence.`
- Primary action: `Save workflow`
- Secondary action: `What did Qaptr misunderstand?`
- Privacy/provenance disclosure: `No source screenshots are included in this explanation.`

### Workflow detail — needs more detail

- Status: `Needs more detail`
- Title: `Compare launch plans and record the decision`
- Rationale: `A product brief and planning document appeared together while tradeoffs were reviewed.`
- Evidence: `4 captures · 12 minutes observed`
- Recommendation: `Capture every 15 seconds for 30 minutes.`
- Primary action: `Capture more detail`
- Secondary: `Keep this explanation`

### Workflow detail — needs more frequent observation

- Status: `Needs more frequent observation`
- Title: `Refine a native interface from review feedback`
- Rationale: `Qaptr saw the same SwiftUI surface, review notes, and repeated visual adjustments.`
- Evidence: `3 captures · 60 minutes observed`
- Recommendation: `Capture every 10 seconds for 20 minutes.`
- Primary action: `Capture more detail`

### Correction states

Design the correction field with:

1. Empty: label `What did Qaptr misunderstand?`, placeholder `Tell Qaptr what to correct…`, button `Submit correction` disabled.
2. Filled: button enabled.
3. Submitting: spinner + `Saving your correction locally…`.
4. Success: `Correction saved. The previous explanation remains available while Qaptr prepares a revision.`
5. Failure: preserve the old explanation, show `Correction could not be saved. Try again.`

## 7. Analysis consent and progress

### Consent sheet

Title: `Review before sending`

Body:

- `Qaptr prepared this request on your Mac. Nothing has been sent yet.`
- Provider: `Claude CLI` / `Codex CLI` / `Jcode CLI`
- Model: `Provider's configured model` or `Model not reported`
- Payload: `Redacted text and scalar context`
- Captures considered: `18`
- Prepared images: `0` or count supplied by the model
- Exclusions: `2 captures excluded`

Boundary copy:

- `Qaptr redacts likely personal information, such as email addresses and phone numbers, on this Mac before any content is shared with a provider.`
- `Qaptr asks again, every time, before sending anything to a provider. Choosing a provider here does not send anything yet.`

Actions:

- Primary: `Approve and analyze`
- Secondary: `Decline`
- The sheet is non-dismissible while awaiting a decision.

### Consent decision states

- Approving: `Starting analysis…`
- Declined: `Nothing was sent` / `The request stayed local because provider consent was declined.`
- Failed to start: `Analysis could not start. Your prepared content stayed local.`

## 8. Observation list and detail

### Observation list with results

Header:

- `What Qaptr found`
- `A calm record of what Qaptr has observed. Capture and analysis stay separate.`

Observation row anatomy:

- Title
- One- or two-sentence summary
- Confidence band: `High`, `Medium`, or `Low`
- Timestamp: e.g. `Today · 10:30 AM`
- Optional provenance: `8 captures · session mock-session`
- Disclosure affordance

### Observation list empty

- Header: `Review`
- Copy: `No observations yet.`
- Detail: `Analyze local captures when you are ready. Qaptr will show the prepared boundary before anything is sent.`
- Action: `Analyze captures`

### Observation list error

- Header: `Review setup`
- Copy: `Qaptr could not load the local review history.`
- Action: `Try again`

### Observation detail sheet

- Title: observation title
- Summary paragraph
- Confidence: `High confidence` with factual basis if available
- Created: `August 23, 2025 · 10:30 AM`
- Capture reference: scalar ID only, never a source image thumbnail
- Session reference: scalar session ID
- Footer: `This explanation contains no source screenshots or provider payload.`
- Action: `Done`

### Notices

Example notice row:

- Icon: shield/eye-off
- `2 captures were skipped while a protected application was active.`
- Use count and reason only. Do not expose excluded app names unless the settings surface explicitly owns that configuration.

## 9. Settings

Settings is a grouped native form with a maximum content width around 620 px.

### Settings sections

1. Capture
2. Detailed capture
3. Privacy and permissions
4. Provider
5. Exclusions

### S1 — Capture section, running

- Status title: `Capture running`
- Detail: `The helper owns capture timing in the background.`
- Action: `Pause`
- Picker: `Capture cadence` → `Every 15 seconds`, `Every 30 seconds`, `Every 1 minute`, `Every 5 minutes`
- Picker: `Keep local captures for` → `12 hours`, `1 day`, `3 days`, `7 days`, `14 days`, `30 days`
- Label: `Displays available` → `1`
- Footer: `Cadence changes are written to the helper's scalar control file. Screenshots remain local until an explicit analysis consent.`

### S2 — Capture paused

- Title: `Capture paused`
- Detail: `No new ticks will start until you resume.`
- Action: `Resume`

### S3 — Capture permission required

- Title: `Screen Recording required`
- Detail: `Grant Screen Recording permission to continue.`
- Action: `Review privacy`

### S4 — Capture needs attention

- Title: `Capture needs attention`
- Detail: `The background helper is not running.`
- Action: `Try again`
- Optional inline error: `The helper could not be restarted.`

### S5 — Detailed capture

- Picker: `Detailed session duration` → `15 minutes`, `30 minutes`, `1 hour`, `2 hours`
- Default action: `Capture more detail now`
- Active action: `Stop detailed capture`
- Footer: `The lightweight helper changes cadence locally and stays active only while the helper reports a real session.`
- Unavailable state: `QaptrHelper is not available. Start the helper, then try again.`

### S6 — Privacy and permissions

Show two live rows:

- `Screen Recording` — `Granted`, `Needs permission`, `Not yet requested`, or `Unavailable` — action `Review privacy`
- `App and window names` — same status values — action `Allow optional context`

Supporting copy:

- `Screen Recording is required for capture.`
- `App and window names are optional context.`
- `Capture stays local until you choose an analysis session.`

### S7 — Provider, no provider

- Title: `Analysis provider`
- Detail: `Choose a provider before analysis. Choosing one does not send anything.`
- Options:
  - `Claude CLI`
  - `Codex CLI`
  - `Jcode CLI`
  - `OpenRouter`
- Unselected action: `Choose`

### S8 — Provider selected but not connected

- Selected provider: `Claude CLI`
- Status: `Needs connection`
- Detail: `Reconnect Claude CLI in Settings before analyzing.`
- Action: `Connect`

### S9 — Provider connected

- Selected provider: `Claude CLI`
- Status: `Connected`
- Detail: `Ready for an explicit analysis session.`
- Action: `Change provider` or `Reconnect`

### S10 — Exclusions

Two editable lists:

- `Excluded applications`
- `Excluded window titles`

Empty state: `No exclusions added.`

Input placeholders:

- `Application name`
- `Window title`

Actions:

- `Add`
- Remove icon with accessible label `Remove exclusion`

Privacy footer: `Excluded contexts are skipped before analysis preparation.`

## 10. Provider setup sheet

Current focused sheet is for OpenRouter. Local CLI providers should use the same status grammar without asking for a raw API key.

### P1 — OpenRouter empty

- Title: `Connect OpenRouter`
- Detail: `Paste your key to check the connection.`
- Privacy note: `Your key stays in your Mac Keychain. This check sends no screenshots or notes.`
- Secure field: `OpenRouter key`
- Primary action: `Verify connection` disabled until text exists.
- Secondary: `Done`
- Quiet action: `Disconnect` only when configured.

### P2 — Checking

- Field disabled.
- Progress row: `Checking`
- Primary action disabled.

### P3 — Connected

- Status: green dot + `OpenRouter is connected`
- Primary label: `Connected`
- Secondary: `Done`

### P4 — Failed

- Error block example: `The provider rejected the key. Check it and try again.`
- Preserve entered field where safe.
- Action: `Verify connection`

## 11. Menu-bar companion

The menu bar is compact and action-oriented. It does not contain workflow explanations, thumbnails, provider controls, or analysis execution controls.

### M1 — Normal, capture on

- Template icon.
- Header: `Qaptr`
- Status: `Capture on`
- Detail: `18 captures`
- Action: `Pause capture`
- Action: `Open Qaptr`
- Action: `Settings`
- Footer: `Quit Qaptr`

### M2 — Paused

- Status: `Capture paused`
- Action: `Resume capture`
- `Open Qaptr`
- `Settings`
- `Quit Qaptr`

### M3 — Needs attention

- Status: `Capture needs attention`
- Detail: `Screen Recording permission required` or helper recovery reason.
- Action: `Review privacy` or `Restart capture`
- `Open Qaptr`
- `Settings`

### M4 — Detailed capture active

- Distinct but monochrome template icon.
- Status: `Detailed capture`
- Remaining: `18m 42s remaining`
- Detail: `7 detailed captures`
- Primary action: `Stop detailed capture and review`
- Secondary action: `Return to normal capture`
- `Settings`
- `Open Qaptr`

### M5 — Analysis preparing

- Status: `Preparing local review`
- Detail: `Protecting captures on this Mac`
- Action: `Open Qaptr`
- No bouncing animation or notification by default.

### M6 — Approval ready

- Status: `Approval ready`
- Detail: `Review the privacy boundary in Qaptr`
- Action: `Open Qaptr`

### M7 — Analyzing

- Status: `Qaptr is analyzing`
- Detail: `The approved context is being reviewed`
- Action: `Open Qaptr`

### M8 — Analysis available

- Status: `Analysis available`
- Detail: `Your capture summary is ready`
- Action: `Open Qaptr`

### M9 — Recovery

- Status: `Analysis needs attention`
- Detail: `The last analysis could not finish`
- Action: `Open Qaptr`

## 12. Canonical mock data

Use this as the default Figma prototype data. Timestamps are illustrative and should display as friendly relative or local dates.

### Capture state

```json
{
  "intent": "running",
  "status": "waiting",
  "captureCount": 18,
  "lastCapture": "2025-08-23T10:30:00-07:00",
  "startedAt": "2025-08-23T09:30:00-07:00",
  "selectedDisplays": ["main-display"],
  "activeIntervalSeconds": 30,
  "screenRecording": "granted",
  "accessibilityContext": "notDetermined"
}
```

### Observations

```json
[
  {
    "id": "mock-observation-1",
    "title": "You compared two launch plans",
    "summary": "A product brief and a planning document were open together while you weighed the tradeoffs between a fast beta and a broader launch.",
    "confidence": 0.91,
    "confidenceBand": "High",
    "createdAt": "2025-08-23T10:30:00-07:00",
    "captureCount": 8,
    "sessionId": "mock-session"
  },
  {
    "id": "mock-observation-2",
    "title": "You were refining the capture experience",
    "summary": "The Qaptr settings surface was open while you adjusted spacing, focus treatment, and the window-title exclusion control.",
    "confidence": 0.84,
    "confidenceBand": "High",
    "createdAt": "2025-08-23T09:30:00-07:00",
    "captureCount": 6,
    "sessionId": "mock-session"
  },
  {
    "id": "mock-observation-3",
    "title": "You reviewed implementation feedback",
    "summary": "A code review and terminal session were visible while you validated a small SwiftUI change against the packaged app.",
    "confidence": 0.73,
    "confidenceBand": "Medium",
    "createdAt": "2025-08-23T08:30:00-07:00",
    "captureCount": 4,
    "sessionId": "mock-session"
  }
]
```

### Workflow candidates

```json
[
  {
    "rank": 1,
    "title": "Validate a product change before release",
    "rationale": "Qaptr repeatedly saw implementation, review feedback, and a packaged-build check in the same work period.",
    "evidenceStatus": "enough_information",
    "evidenceLabel": "Enough information",
    "confidence": 0.91,
    "evidenceBasis": "8 captures across 42 minutes showed the same implementation-to-verification sequence.",
    "captureCount": 8,
    "observedSpan": "42 minutes",
    "recommendation": null
  },
  {
    "rank": 2,
    "title": "Compare launch plans and record the decision",
    "rationale": "A product brief and planning document appeared together while tradeoffs were reviewed.",
    "evidenceStatus": "needs_more_detail",
    "evidenceLabel": "Needs more detail",
    "confidence": 0.73,
    "evidenceBasis": "4 captures show comparison work, but not the final decision or handoff.",
    "captureCount": 4,
    "observedSpan": "12 minutes",
    "recommendation": {
      "intervalSeconds": 15,
      "durationSeconds": 1800,
      "label": "Every 15 seconds for 30 minutes"
    }
  },
  {
    "rank": 3,
    "title": "Refine a native interface from review feedback",
    "rationale": "Qaptr saw the same SwiftUI surface, review notes, and repeated visual adjustments.",
    "evidenceStatus": "needs_more_frequent_observation",
    "evidenceLabel": "Needs more frequent observation",
    "confidence": 0.61,
    "evidenceBasis": "3 captures establish the task, but the important edits happened between observations.",
    "captureCount": 3,
    "observedSpan": "60 minutes",
    "recommendation": {
      "intervalSeconds": 10,
      "durationSeconds": 1200,
      "label": "Every 10 seconds for 20 minutes"
    }
  }
]
```

### Notices

```json
[
  {
    "count": 2,
    "text": "2 captures were skipped while a protected application was active.",
    "tone": "quiet privacy notice"
  }
]
```

### Consent summary

```json
{
  "provider": "Claude CLI",
  "resolvedModel": "claude-sonnet",
  "modelLabel": "Claude Sonnet",
  "payloadKind": "Redacted text and scalar context",
  "captureCount": 18,
  "imageCount": 0,
  "exclusionCount": 2
}
```

### Analysis session states

```json
{
  "idle": {
    "title": "Turn captures into observations",
    "detail": "18 screenshots available. Preparation stays on this Mac."
  },
  "ingesting": {
    "title": "Finding screenshots in your local vault",
    "detail": "Qaptr is opening committed captures. Nothing has left this Mac."
  },
  "preparing": {
    "title": "Protecting screenshots on this Mac",
    "detail": "OCR is extracting text while privacy rules remove sensitive content before approval."
  },
  "readyForConsent": {
    "title": "Ready for your approval",
    "detail": "Review exactly what will be sent before the provider is invoked."
  },
  "analyzing": {
    "title": "Claude CLI is reviewing approved text",
    "detail": "The approved context is being reviewed."
  },
  "completed": {
    "title": "Added 3 observations",
    "detail": "The review result was saved locally."
  },
  "failed": {
    "title": "Analysis needs attention",
    "detail": "The selected provider could not complete the review."
  },
  "cancelled": {
    "title": "Analysis cancelled",
    "detail": "No provider result was saved."
  }
}
```

## 13. Prototype connections

Create these prototype links:

1. F1 primary → macOS permission handoff → F2 or F3.
2. F3 `Continue` → F4.
3. F4 `Start capture` → R2 or R6 depending on available history.
4. R6 `Analyze captures` → R7 ingesting → R7 preparing → R8 consent.
5. R8 `Approve and analyze` → R7 analyzing → R9 candidates ready.
6. R8 `Decline` → R10 insufficient evidence / local-only result.
7. R9 candidate row → workflow detail.
8. Workflow detail `Capture more detail` → approval state / detailed capture confirmation.
9. Review `Settings` → Settings surface; `Review` returns with directional transition.
10. Settings provider action → P1/P2/P3/P4.
11. Observation row → observation detail sheet.
12. Menu-bar `Open Qaptr` → current relevant app state.

## 14. Design review checklist

Before handing off the Figma file:

- [ ] Every state says one clear fact and one next action.
- [ ] No screen implies that a provider was contacted before explicit consent.
- [ ] Screen Recording status can visibly transition from not requested to granted.
- [ ] No screen uses a source screenshot thumbnail as decorative content.
- [ ] Empty, loading, permission, stale helper, unavailable provider, malformed output, cancellation, and failure states are represented.
- [ ] Long titles and long recovery messages do not break the layout.
- [ ] Narrow window versions preserve the primary action.
- [ ] Keyboard focus, disabled, hover, pressed, and reduced-motion variants exist.
- [ ] Candidate ranking is visually clear and not represented as equal cards.
- [ ] Menu-bar states remain compact and do not duplicate the review workspace.
- [ ] The visual system uses semantic tokens rather than one-off colors.
- [ ] A designer can build every screen using only the mock data in this document.
