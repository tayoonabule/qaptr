# Qaptr Screen Inventory and Mock Data

This is a neutral reference for designing Qaptr screens in Figma. It lists what each screen represents, the content it displays, its states, and representative mock data. It does not prescribe visual style, layout, typography, component choices, or interaction design.

## Shared mock data

Use these values unless a screen-specific fixture overrides them.

```json
{
  "appName": "Qaptr",
  "capture": {
    "intent": "running",
    "status": "waiting",
    "captureCount": 18,
    "lastCaptureAt": "2025-08-23T10:30:00-07:00",
    "startedAt": "2025-08-23T09:30:00-07:00",
    "selectedDisplayIDs": ["main-display"],
    "activeIntervalSeconds": 30,
    "screenRecording": "granted",
    "accessibilityContext": "notDetermined"
  },
  "provider": {
    "selected": "claude-cli",
    "displayName": "Claude CLI",
    "connection": "connected"
  }
}
```

### Permission status values

- `notDetermined` — Not yet requested
- `denied` — Needs permission
- `granted` — Granted
- `unavailable` — Unavailable

### Capture status values

- `starting`
- `waiting`
- `capturing`
- `paused`
- `permissionRequired`
- `noDisplays`
- `error`
- `stopped`
- `unknown`

## 1. First-run onboarding

### 1.1 Screen Recording: not requested

**Purpose:** Explain Qaptr's local, occasional capture and request the required Screen Recording permission.

**Visible content:**

- Brand: `Qaptr`
- Eyebrow: `FIRST RUN`
- Title: `Capture your work, quietly.`
- Introduction: `Qaptr takes an occasional screenshot on this Mac so you can review patterns later. Capture stays local until you choose an analysis session.`
- Step indicator: `STEP 1 / 2`
- Heading: `Allow Screen Recording`
- Explanation: `Screen Recording is the one required permission. QaptrHelper owns capture and reports the live result here.`
- Status: `Not yet requested`
- Detail: `Qaptr needs Screen Recording to take an occasional, downscaled screenshot every few minutes. It never records continuously and never uploads a screenshot until you choose to review it.`
- Primary action: `Allow Screen Recording`
- Footer: `You can change privacy and capture choices later in Settings.`

**Mock data:**

```json
{
  "screenRecording": "notDetermined",
  "accessibilityContext": "notDetermined",
  "availableDisplayIDs": ["main-display"],
  "onboardingCompleted": false
}
```

### 1.2 Screen Recording: permission denied or not enabled

**Purpose:** Tell the person that Screen Recording still needs to be enabled and provide a route back to macOS settings.

**Visible changes from 1.1:**

- Status: `Needs permission`
- Primary action: `Open System Settings`

**Optional recovery text:** `Enable QaptrHelper in Screen Recording, then return to Qaptr.`

**Mock data:**

```json
{
  "screenRecording": "denied",
  "accessibilityContext": "notDetermined",
  "availableDisplayIDs": ["main-display"],
  "onboardingCompleted": false
}
```

### 1.3 Screen Recording: granted

**Purpose:** Confirm the required permission and allow the person to continue.

**Visible changes from 1.1:**

- Status icon/state: granted
- Status: `Granted`
- Supporting text: `When you finish this step, capture starts immediately. There is no separate start screen.`
- Primary action: `Continue`

**Mock data:**

```json
{
  "screenRecording": "granted",
  "accessibilityContext": "notDetermined",
  "availableDisplayIDs": ["main-display"],
  "onboardingCompleted": false
}
```

### 1.4 Optional context

**Purpose:** Offer optional Accessibility context after Screen Recording is granted.

**Visible content:**

- Step indicator: `STEP 2 / 2`
- Heading: `Add optional context`
- Explanation: `Optional: allow Qaptr to read the frontmost app and window title. This adds context, but capture does not depend on it.`
- Status row title: `App and window names`
- Status: one permission status value
- Secondary action: `Allow optional context`
- Primary action: `Start capture`
- Quiet action: `Start without optional context`

**Conditional content:**

- No display: `Connect at least one display before capture can begin.`
- Completion failure: `Qaptr could not finish setup yet. Check the live permission and helper status, then try again.`

**Mock data:**

```json
{
  "screenRecording": "granted",
  "accessibilityContext": "notDetermined",
  "availableDisplayIDs": ["main-display"],
  "onboardingCompleted": false
}
```

## 2. Returning review workspace

The review workspace can show workflow candidates, observations, analysis states, empty states, and recovery states.

### 2.1 Loading

**Purpose:** Show that local review history is being loaded.

**Visible content:**

- Title: `Review`
- Status text: `Loading your local review history.`

**Mock data:**

```json
{
  "hasLoaded": false,
  "loadError": null,
  "observations": [],
  "workflowCandidates": []
}
```

### 2.2 No captures

**Purpose:** Explain that there are no local captures to review yet.

**Visible content:**

- Title: `Review`
- Message: `Qaptr has not captured anything yet.`
- Detail: `When the helper makes its first local capture, it will appear here.`
- Possible action: `Open Settings`

**Mock data:**

```json
{
  "hasLoaded": true,
  "captureCount": 0,
  "observations": [],
  "workflowCandidates": [],
  "captureStatus": "waiting"
}
```

### 2.3 Capture unavailable

**Purpose:** Explain that the review surface cannot confirm the helper's state.

**Visible content:**

- Title: `Review setup`
- Message: `Capture status unavailable`
- Detail: `Qaptr cannot confirm the helper's current state.`
- Action: `Try again`

**Mock data:**

```json
{
  "hasLoaded": true,
  "captureCount": null,
  "captureStatus": "unknown",
  "observations": [],
  "workflowCandidates": []
}
```

### 2.4 Capture permission required

**Purpose:** Explain why capture is not available.

**Visible content:**

- Message: `Capture permission needed`
- Detail: `Grant Screen Recording permission to continue.`
- Action: `Review privacy`

**Mock data:**

```json
{
  "captureStatus": "permissionRequired",
  "screenRecording": "denied",
  "captureCount": 0
}
```

### 2.5 Provider setup needed

**Purpose:** Ask the person to configure a provider before analysis.

**Visible content:**

- Title: `Connect a provider to analyze captures`
- Detail: `Your captures are local. Choose a supported provider in Settings when you are ready to create observations.`
- Action: `Open Settings`
- Privacy text: `Nothing is sent by choosing a provider. Qaptr asks separately before each analysis session.`

**Mock data:**

```json
{
  "captureCount": 18,
  "provider": null,
  "observations": [],
  "workflowCandidates": []
}
```

### 2.6 Ready to analyze

**Purpose:** Offer analysis when local captures and a connected provider are available.

**Visible content:**

- Title: `Turn captures into observations`
- Detail: `18 screenshots available. Preparation stays on this Mac.`
- Action: `Analyze captures`
- Privacy text: `Qaptr will prepare and redact content locally before asking for consent.`

**Mock data:**

```json
{
  "captureCount": 18,
  "provider": {
    "selected": "claude-cli",
    "displayName": "Claude CLI",
    "connection": "connected"
  },
  "analysisPhase": "idle",
  "observations": [],
  "workflowCandidates": []
}
```

### 2.7 Analysis working: ingesting

**Purpose:** Show local capture ingestion before preparation.

**Visible content:**

- Title: `Finding screenshots in your local vault`
- Detail: `Qaptr is opening committed captures. Nothing has left this Mac.`
- Action: `Cancel`

**Mock data:**

```json
{
  "analysisPhase": "ingesting",
  "capturesSeen": 18,
  "preparedCaptures": 0,
  "imageCount": 0,
  "exclusionCount": 0,
  "providerCallStarted": false
}
```

### 2.8 Analysis working: preparing

**Purpose:** Show local OCR and privacy preparation.

**Visible content:**

- Title: `Protecting screenshots on this Mac`
- Detail: `OCR is extracting text while privacy rules remove sensitive content before approval.`
- Action: `Cancel`

**Mock data:**

```json
{
  "analysisPhase": "preparing",
  "capturesSeen": 18,
  "preparedCaptures": 16,
  "imageCount": 0,
  "exclusionCount": 2,
  "providerCallStarted": false
}
```

### 2.9 Analysis working: provider analysis

**Purpose:** Show analysis after the person has approved the prepared request.

**Visible content:**

- Title: `Claude CLI is reviewing approved text`
- Detail: `The approved context is being reviewed.`
- Action: `Cancel`

**Mock data:**

```json
{
  "analysisPhase": "analyzing",
  "provider": "Claude CLI",
  "capturesSeen": 18,
  "preparedCaptures": 16,
  "imageCount": 0,
  "exclusionCount": 2,
  "providerCallStarted": true
}
```

### 2.10 Consent required

**Purpose:** Indicate that local preparation is complete and the person must review the request before the provider is invoked.

**Visible content behind the sheet:**

- Title: `Ready for your approval`
- Detail: `Review exactly what will be sent before the provider is invoked.`
- Status: `CONSENT REQUIRED`

**Mock data:**

```json
{
  "analysisPhase": "readyForConsent",
  "consentSummaryId": "consent-001",
  "providerCallStarted": false
}
```

### 2.11 Candidates ready

**Purpose:** Display ranked workflow candidates returned by analysis.

**Visible content:**

- Header: `What Qaptr found`
- Supporting text: `A calm record of what Qaptr has observed. Capture and analysis stay separate.`
- A ranked list of workflow candidates.

**Mock data:**

```json
{
  "workflowCandidates": [
    {
      "id": "mock-candidate-1",
      "rank": 1,
      "title": "Validate a product change before release",
      "rationale": "Qaptr repeatedly saw implementation, review feedback, and a packaged-build check in the same work period.",
      "evidenceStatus": "enough_information",
      "evidenceConfidence": 0.91,
      "evidenceBasis": "8 captures across 42 minutes showed the same implementation-to-verification sequence.",
      "evidenceCaptureCount": 8,
      "observedStartAt": "2025-08-23T09:48:00-07:00",
      "observedEndAt": "2025-08-23T10:30:00-07:00"
    },
    {
      "id": "mock-candidate-2",
      "rank": 2,
      "title": "Compare launch plans and record the decision",
      "rationale": "A product brief and planning document appeared together while tradeoffs were reviewed.",
      "evidenceStatus": "needs_more_detail",
      "evidenceConfidence": 0.73,
      "evidenceBasis": "4 captures show comparison work, but not the final decision or handoff.",
      "evidenceCaptureCount": 4,
      "recommendation": {
        "intervalSeconds": 15,
        "durationSeconds": 1800
      }
    },
    {
      "id": "mock-candidate-3",
      "rank": 3,
      "title": "Refine a native interface from review feedback",
      "rationale": "Qaptr saw the same SwiftUI surface, review notes, and repeated visual adjustments.",
      "evidenceStatus": "needs_more_frequent_observation",
      "evidenceConfidence": 0.61,
      "evidenceBasis": "3 captures establish the task, but the important edits happened between observations.",
      "evidenceCaptureCount": 3,
      "recommendation": {
        "intervalSeconds": 10,
        "durationSeconds": 1200
      }
    }
  ]
}
```

### 2.12 Insufficient evidence

**Purpose:** Explain that analysis completed but did not produce a supported workflow candidate.

Possible messages:

- `No privacy-safe capture content was eligible for this analysis.`
- `The request stayed local because provider consent was declined.`
- `Analysis completed without a supported workflow candidate result.`

**Optional recommendation:**

- Title: `Capture more detail`
- Detail: `Every 15 seconds for 30 minutes`
- Action: `Review detailed capture`

**Mock data:**

```json
{
  "analysisPhase": "completed",
  "outcome": "no_eligible_payload",
  "observationsWritten": 0,
  "workflowCandidates": []
}
```

### 2.13 Evidence without candidates

**Purpose:** Show that observations were saved even though no workflow candidate was produced.

**Visible content:**

- Title: `Observations are ready`
- Detail: `Qaptr wrote 5 observations, but did not produce a supported workflow candidate.`
- Actions: `View observations`, `Analyze again`

**Mock data:**

```json
{
  "analysisPhase": "completed",
  "observationsWritten": 5,
  "workflowCandidates": []
}
```

### 2.14 Analysis failed

**Purpose:** Explain that the analysis session failed and provide recovery.

**Visible content:**

- Title: `Analysis needs attention`
- Detail: `The selected provider could not complete the review.`
- Actions: `Try again`, `Open Settings`

**Mock data:**

```json
{
  "analysisPhase": "failed",
  "analysisError": "The selected provider could not complete the review.",
  "allowedOperations": ["retry", "state"]
}
```

### 2.15 Analysis cancelled

**Purpose:** Confirm cancellation.

**Visible content:**

- Title: `Analysis cancelled`
- Detail: `No provider result was saved.`
- Action: `Analyze captures`

**Mock data:**

```json
{
  "analysisPhase": "cancelled",
  "outcome": "cancelled",
  "observationsWritten": 0
}
```

## 3. Workflow detail

### 3.1 Candidate with enough information

**Purpose:** Explain a workflow candidate and show the evidence behind it.

**Visible content:**

- Rank: `01`
- Evidence status: `Enough information`
- Title: `Validate a product change before release`
- Rationale: `Qaptr repeatedly saw implementation, review feedback, and a packaged-build check in the same work period.`
- Evidence basis: `8 captures across 42 minutes showed the same implementation-to-verification sequence.`
- Evidence count: `8 captures`
- Observed time span: `42 minutes`
- Actions: `Save workflow`, `What did Qaptr misunderstand?`

**Mock data:** Use `mock-candidate-1` from Section 2.11.

### 3.2 Candidate needing more detail

**Purpose:** Explain that more context is needed and show the suggested capture plan.

**Visible content:**

- Evidence status: `Needs more detail`
- Title: `Compare launch plans and record the decision`
- Rationale: `A product brief and planning document appeared together while tradeoffs were reviewed.`
- Evidence basis: `4 captures show comparison work, but not the final decision or handoff.`
- Recommendation: `Every 15 seconds for 30 minutes`
- Action: `Capture more detail`
- Secondary action: `Keep this explanation`

**Mock data:** Use `mock-candidate-2` from Section 2.11.

### 3.3 Candidate needing more frequent observation

**Purpose:** Explain that the task is visible but the observation cadence missed important changes.

**Visible content:**

- Evidence status: `Needs more frequent observation`
- Title: `Refine a native interface from review feedback`
- Rationale: `Qaptr saw the same SwiftUI surface, review notes, and repeated visual adjustments.`
- Evidence basis: `3 captures establish the task, but the important edits happened between observations.`
- Recommendation: `Every 10 seconds for 20 minutes`
- Action: `Capture more detail`

**Mock data:** Use `mock-candidate-3` from Section 2.11.

### 3.4 Correction field: empty

**Purpose:** Let the person tell Qaptr what it misunderstood.

**Visible content:**

- Label: `What did Qaptr misunderstand?`
- Placeholder: `Tell Qaptr what to correct…`
- Action: `Submit correction` disabled while empty.

### 3.5 Correction field: submitting

**Visible content:**

- Entered correction text remains visible.
- Progress: `Saving your correction locally…`
- Submit action disabled.

### 3.6 Correction field: saved

**Visible content:**

- Message: `Correction saved. The previous explanation remains available while Qaptr prepares a revision.`

### 3.7 Correction field: failed

**Visible content:**

- Error: `Correction could not be saved. Try again.`
- Previous workflow explanation remains visible.
- Action: `Try again`

## 4. Analysis consent sheet

### 4.1 Consent pending

**Purpose:** Show the exact scalar summary of the prepared request before a provider is invoked.

**Visible content:**

- Title: `Review before sending`
- Intro: `Qaptr prepared this request on your Mac. Nothing has been sent yet.`
- Provider: `Claude CLI`
- Model: `Claude Sonnet`
- Payload: `Redacted text and scalar context`
- Captures considered: `18`
- Prepared images: `0`
- Exclusions: `2 captures excluded`
- Privacy text: `Qaptr redacts likely personal information, such as email addresses and phone numbers, on this Mac before any content is shared with a provider.`
- Consent text: `Qaptr asks again, every time, before sending anything to a provider. Choosing a provider here does not send anything yet.`
- Actions: `Approve and analyze`, `Decline`

**Mock data:**

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

### 4.2 Consent approving

- Status: `Starting analysis…`
- Primary action disabled while the request starts.

### 4.3 Consent declined

- Title: `Nothing was sent`
- Detail: `The request stayed local because provider consent was declined.`

### 4.4 Consent start failed

- Title: `Analysis could not start`
- Detail: `Your prepared content stayed local.`
- Action: `Close` or `Try again`, depending on the current session state.

## 5. Observations

### 5.1 Observation list with results

**Purpose:** Display durable observations in reverse chronological order.

**Header:**

- `What Qaptr found`
- `A calm record of what Qaptr has observed. Capture and analysis stay separate.`

**Row data:**

```json
[
  {
    "id": "mock-observation-1",
    "title": "You compared two launch plans",
    "summary": "A product brief and a planning document were open together while you weighed the tradeoffs between a fast beta and a broader launch.",
    "confidence": 0.91,
    "createdAt": "2025-08-23T10:30:00-07:00",
    "captureID": "mock-capture-1",
    "sessionID": "mock-session"
  },
  {
    "id": "mock-observation-2",
    "title": "You were refining the capture experience",
    "summary": "The Qaptr settings surface was open while you adjusted spacing, focus treatment, and the window-title exclusion control.",
    "confidence": 0.84,
    "createdAt": "2025-08-23T09:30:00-07:00",
    "captureID": "mock-capture-2",
    "sessionID": "mock-session"
  },
  {
    "id": "mock-observation-3",
    "title": "You reviewed implementation feedback",
    "summary": "A code review and terminal session were visible while you validated a small SwiftUI change against the packaged app.",
    "confidence": 0.73,
    "createdAt": "2025-08-23T08:30:00-07:00",
    "captureID": "mock-capture-3",
    "sessionID": "mock-session"
  }
]
```

### 5.2 Observation list empty

- Title: `Review`
- Message: `No observations yet.`
- Detail: `Analyze local captures when you are ready. Qaptr will show the prepared boundary before anything is sent.`
- Action: `Analyze captures`

### 5.3 Observation list load error

- Title: `Review setup`
- Message: `Qaptr could not load the local review history.`
- Action: `Try again`

### 5.4 Observation detail

**Purpose:** Show one observation's full scalar explanation.

**Visible content:**

- Observation title: `You compared two launch plans`
- Summary: use the corresponding observation summary.
- Confidence: `High confidence`
- Created: `August 23, 2025 · 10:30 AM`
- Capture reference: `mock-capture-1`
- Session reference: `mock-session`
- Privacy note: `This explanation contains no source screenshots or provider payload.`
- Action: `Done`

### 5.5 Exclusion notices

**Purpose:** Explain why some captures did not appear in the review.

**Mock data:**

```json
{
  "count": 2,
  "text": "2 captures were skipped while a protected application was active."
}
```

## 6. Settings

Settings contains capture, detailed capture, privacy, provider, and exclusion sections.

### 6.1 Capture: running

- Status title: `Capture running`
- Detail: `The helper owns capture timing in the background.`
- Action: `Pause`
- Capture cadence: `Every 30 seconds`
- Local retention: `1 day`
- Displays available: `1`
- Footer: `Cadence changes are written to the helper's scalar control file. Screenshots remain local until an explicit analysis consent.`

**Mock data:**

```json
{
  "captureIntent": "running",
  "captureProgress": "waiting",
  "helperIsRunning": true,
  "intervalSeconds": 30,
  "cacheLifetime": "oneDay",
  "availableDisplays": ["main-display"]
}
```

### 6.2 Capture: paused

- Title: `Capture paused`
- Detail: `No new ticks will start until you resume.`
- Action: `Resume`

```json
{
  "captureIntent": "paused",
  "helperIsRunning": true,
  "intervalSeconds": 30
}
```

### 6.3 Capture: permission required

- Title: `Screen Recording required`
- Detail: `Grant Screen Recording permission to continue.`
- Action: `Review privacy`

```json
{
  "captureProgress": "permissionRequired",
  "screenRecording": "denied"
}
```

### 6.4 Capture: no display

- Title: `No display available`
- Detail: `Connect a display before Qaptr can capture.`
- No recovery action is required on this row.

```json
{
  "captureProgress": "noDisplays",
  "availableDisplays": []
}
```

### 6.5 Capture: needs attention

- Title: `Capture needs attention`
- Detail: `The background helper is not running.`
- Action: `Try again`

```json
{
  "captureProgress": "error",
  "helperIsRunning": false,
  "helperProcessExists": false
}
```

### 6.6 Detailed capture: inactive

- Section title: `Detailed capture`
- Duration picker: `1 hour`
- Action: `Capture more detail now`
- Footer: `The lightweight helper changes cadence locally. Stop the session to restore the normal cadence.`

### 6.7 Detailed capture: active

- Duration: `1 hour`
- Action: `Stop detailed capture`
- Example status: `23 minutes remaining`
- Example count: `7 detailed captures`

```json
{
  "detailedCaptureState": "capturing",
  "durationSeconds": 3600,
  "remainingSeconds": 1380,
  "detailedCaptureCount": 7
}
```

### 6.8 Detailed capture: helper unavailable

- Message: `QaptrHelper is not available. Start the helper, then try again.`

### 6.9 Privacy and permissions

Rows:

- `Screen Recording`
- `App and window names`

Each row can show `Granted`, `Needs permission`, `Not yet requested`, or `Unavailable`.

Supporting text:

- `Screen Recording is required for capture.`
- `App and window names are optional context.`
- `Capture stays local until you choose an analysis session.`

### 6.10 Provider: none selected

- Section title: `Analysis provider`
- Detail: `Choose a provider before analysis. Choosing one does not send anything.`
- Provider options: `Claude CLI`, `Codex CLI`, `Jcode CLI`, `OpenRouter`
- Action for an option: `Choose`

```json
{
  "provider": null,
  "providerConnection": "notConnected"
}
```

### 6.11 Provider: selected but not connected

- Selected provider: `Claude CLI`
- Status: `Needs connection`
- Detail: `Reconnect Claude CLI in Settings before analyzing.`
- Action: `Connect`

```json
{
  "provider": "claude-cli",
  "providerConnection": "notConnected"
}
```

### 6.12 Provider: connected

- Selected provider: `Claude CLI`
- Status: `Connected`
- Detail: `Ready for an explicit analysis session.`
- Action: `Reconnect` or `Change provider`

```json
{
  "provider": "claude-cli",
  "providerConnection": "connected"
}
```

### 6.13 Exclusions: empty

- Section title: `Excluded applications`
- Empty text: `No exclusions added.`
- Input: `Application name`
- Action: `Add`

- Section title: `Excluded window titles`
- Empty text: `No exclusions added.`
- Input: `Window title`
- Action: `Add`

### 6.14 Exclusions: populated

```json
{
  "excludedApplications": ["1Password", "Keychain Access"],
  "excludedWindowTitles": ["Private notes", "Personal finance"]
}
```

## 7. Provider setup sheet

### 7.1 OpenRouter: empty

- Title: `Connect OpenRouter`
- Detail: `Paste your key to check the connection.`
- Privacy text: `Your key stays in your Mac Keychain. This check sends no screenshots or notes.`
- Secure field placeholder: `OpenRouter key`
- Action: `Verify connection` disabled until a key is entered.
- Action: `Done`

### 7.2 OpenRouter: checking

- Secure field disabled.
- Progress: `Checking`
- Verify action disabled.

```json
{
  "provider": "openrouter",
  "connection": "checking",
  "keyPresent": true
}
```

### 7.3 OpenRouter: connected

- Status: `OpenRouter is connected`
- Action label: `Connected`
- Action: `Done`

```json
{
  "provider": "openrouter",
  "connection": "connected",
  "keyPresent": true
}
```

### 7.4 OpenRouter: failed

- Error example: `The provider rejected the key. Check it and try again.`
- Action: `Verify connection`
- Action: `Done`

```json
{
  "provider": "openrouter",
  "connection": "failed",
  "error": "The provider rejected the key. Check it and try again."
}
```

## 8. Menu-bar companion

### 8.1 Normal: capture on

- App label: `Qaptr`
- Status: `Capture on`
- Detail: `18 captures`
- Actions: `Pause capture`, `Open Qaptr`, `Settings`, `Quit Qaptr`

### 8.2 Paused

- Status: `Capture paused`
- Actions: `Resume capture`, `Open Qaptr`, `Settings`, `Quit Qaptr`

### 8.3 Needs attention

- Status: `Capture needs attention`
- Detail example: `Screen Recording permission required`
- Actions: `Review privacy` or `Restart capture`, `Open Qaptr`, `Settings`, `Quit Qaptr`

### 8.4 Detailed capture

- Status: `Detailed capture`
- Remaining: `18m 42s remaining`
- Detail: `7 detailed captures`
- Actions: `Stop detailed capture and review`, `Return to normal capture`, `Settings`, `Open Qaptr`

```json
{
  "menuState": "detailed",
  "remainingSeconds": 1122,
  "detailedCaptureCount": 7,
  "normalCaptureCount": 18
}
```

### 8.5 Analysis activity

Use one of these states:

```json
[
  {
    "status": "Preparing local review",
    "detail": "Protecting captures on this Mac"
  },
  {
    "status": "Approval ready",
    "detail": "Review the privacy boundary in Qaptr"
  },
  {
    "status": "Qaptr is analyzing",
    "detail": "The approved context is being reviewed"
  },
  {
    "status": "Analysis available",
    "detail": "Your capture summary is ready"
  },
  {
    "status": "Analysis needs attention",
    "detail": "The last analysis could not finish"
  }
]
```

All activity states have the action `Open Qaptr`.

## 9. Minimum Figma screen set

For a complete first-pass file, create one frame for each of the following:

1. Onboarding — Screen Recording not requested
2. Onboarding — Screen Recording denied
3. Onboarding — Screen Recording granted
4. Onboarding — Optional context
5. Review — Loading
6. Review — No captures
7. Review — Permission required
8. Review — Provider setup needed
9. Review — Ready to analyze
10. Review — Analysis preparing
11. Review — Consent required
12. Review — Candidates ready
13. Review — Insufficient evidence
14. Review — Analysis failed
15. Workflow — Enough information
16. Workflow — Needs more detail
17. Workflow — Needs more frequent observation
18. Workflow — Correction states
19. Consent sheet — Pending
20. Consent sheet — Declined
21. Observations — Results
22. Observations — Empty
23. Observation detail
24. Settings — Running
25. Settings — Paused
26. Settings — Permission required
27. Settings — Provider states
28. Settings — Exclusions
29. Provider sheet — Empty
30. Provider sheet — Checking
31. Provider sheet — Connected
32. Provider sheet — Failed
33. Menu bar — Normal
34. Menu bar — Paused
35. Menu bar — Needs attention
36. Menu bar — Detailed capture
37. Menu bar — Analysis activity
