# Qaptr product truth

## What Qaptr is

Qaptr is a small macOS app that takes occasional screenshots, keeps them private on the device, and helps a person turn useful work into clear notes.

## Who it is for

People doing computer work who want to remember useful steps without recording everything they do.

## What a person needs to do

1. Let Qaptr take screenshots.
2. Choose how often it takes them.
3. Tell Qaptr what apps and windows to leave alone.
4. Connect an analysis tool, or use capture-only mode.
5. Review a session and choose whether to share approved, redacted text with that tool.

## Product promises

- Qaptr explains what it needs before it asks.
- Qaptr never calls an analysis provider just because it was selected.
- Qaptr tells the truth about setup. It does not claim capture, permissions, or a provider is ready until the owning process confirms it.
- Sensitive apps and windows are excluded before a capture is sealed.
- A provider key stays in the macOS Keychain, never in settings or readable UI state.
- All default copy is short, concrete, and easy to read.

## Product boundaries

- The helper owns capture and reports its state.
- The review app owns navigation, Keychain credentials, provider connection state, consent, and history review.
- The website explains the product and collects an email. It does not pretend to be the app.
- A provider connection only proves setup. Each analysis still needs session-level consent.

## Core states

### Capture

- Needs permission
- Not running
- Running
- Paused
- Needs attention

### Provider

- Not connected
- Needs sign-in or key
- Checking
- Connected
- Could not connect

### Review

- Loading
- No captures yet
- Ready to review
- Waiting for your approval
- Reviewing
- Nothing found
- Results ready
- Could not load

## Success

A person can open Qaptr, understand its state in a few seconds, change one setting without hunting, connect OpenRouter with a key prompt, see an honest connected result, and know exactly what happens next.
