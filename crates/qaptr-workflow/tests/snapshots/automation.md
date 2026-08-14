# Automation Procedure: Weekly exception review

> Descriptive plan only. Qaptr does not launch tools, emit executable commands, or execute automations.

## Automation boundary

- **Execution status:** NOT EXECUTED BY QAPTR
- **Automation contract:** Translate the observed actions below into a separately reviewed implementation; this export itself performs no action
- **Workflow evidence:** HIGH (92%) — Repeated in the observed session

## Purpose and preconditions

- **Goal:** Prepare the reviewed report for the weekly operations meeting
- **Context:** Operations reviews a dated CSV before the weekly meeting

## Inputs

- **Source CSV** (required) — A dated export supplied by the operations team
  - **Evidence:** HIGH (92%) — Repeated in the observed session
- **Optional notes** (optional) — No description was captured.
  - **Evidence:** MODERATE (68%) — Observed once

## Observed tool capabilities

- **Spreadsheet editor** — Inspect and annotate the source. Observed use: The operator filtered rows and added review notes
  - **Evidence:** HIGH (92%) — Repeated in the observed session

## Procedure model

1. **Open the source** — Open the dated CSV in the spreadsheet editor
  - **Why:** Establish the review period before filtering
  - **Consumes:** Source CSV
  - **Produces:** Open review sheet
  - **Tool capabilities:** Spreadsheet editor
  - **Evidence:** HIGH (92%) — Repeated in the observed session

2. **Review exceptions** — Filter rows marked for follow-up and add notes
  - **Why:** Separate items that need an owner decision
  - **Consumes:** Open review sheet
  - **Produces:** Reviewed report
  - **Tool capabilities:** Spreadsheet editor
  - **Evidence:** LOW (32%) — Partial evidence only

## Branching logic

- **Condition:** Does the row have a follow-up marker?
- **Observed path:** Add it to the reviewed report
  - If No marker → Leave the row unchanged
  - **Evidence:** MODERATE (68%) — Observed once

## Known variations

- **Missing source date** when The export has no date in its filename: Ask the operations owner to confirm the review period before continuing
  - **Evidence:** LOW (32%) — Partial evidence only

## Outputs

- **Reviewed report** (required) — A report ready for the weekly review
  - **Evidence:** HIGH (92%) — Repeated in the observed session

## Source trace

- **Session:** session-42
- **Observations:** observation-7
- **Captures:** capture-3
- **Note:** Observed during a fixed review session
