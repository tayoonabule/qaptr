# Qaptr design system

## Direction

A quiet, native productivity utility. It should feel as familiar as a thoughtful macOS app, as clear as ChatGPT, and as organized as Notion. It is not a magazine, a dashboard, or a settings demo.

## Design choices

- **Mode:** Operate. The interface helps a person do a small job with confidence.
- **Typography:** System sans only in the native app. No display serif. No monospaced type as decoration.
- **Shape:** 12-point rounded containers where grouping matters. Native controls otherwise stay close to platform form.
- **Color:** Cool neutral surfaces, strong ink text, and Qaptr amber for deliberate actions. Status colors only communicate real state.
- **Spacing:** Tight enough to scan. One clear content column. No oversized title blocks, ornamental dividers, or empty fields.
- **Motion:** A 160-200ms fade for navigation and a subtle press response. No springs, rails, loops, or motion that hides state.
- **Copy:** A short title, one sentence when needed, and a named action. Use familiar words. Do not expose internal errors.

## Native shell

The signed-in app has two destinations:

- **Review:** The state of capture and the next useful action.
- **Settings:** Capture, privacy, and analysis setup.

At the compact app size, navigation is a small sidebar or a clear segmented top bar. It never becomes a large page header with an underlined link.

## Settings rules

- Show only the setting and its current value.
- Open a focused sheet when a choice needs explanation.
- Show a saved confirmation after an accepted setting change.
- Keep provider setup in a dedicated provider sheet.
- Keep exclusions in a focused editor with clear examples, inline validation, and focus returned to the input after adding an item.
- Do not call a value active until the helper or provider has confirmed it.

## Provider connection rules

A provider row is one of these states:

- Not connected: a single **Connect** action.
- Needs key: selecting OpenRouter opens a secure key sheet immediately.
- Checking: the action is disabled and says **Checking**.
- Connected: a visible success mark, provider name, and **Manage** action.
- Could not connect: a short reason, then **Try again** and **Change key**.

A selected provider and a connected provider are different things. The UI must never blur them.

## State and feedback rules

- Put focus on a new sheet title when it opens.
- Return focus to the control that opened a sheet after it closes.
- Escape closes a sheet or returns one onboarding step.
- Use a success checkmark and concise confirmation after a completed action.
- Respect Reduce Motion by making transitions immediate.
- Use accessible labels that include the item name for destructive actions.

## Website alignment

The website uses the same cool-neutral surface, cobalt action color, system-forward sans typography, plain copy, and calm interactions. It uses real Qaptr output or real photography, never invented dashboard screenshots.
