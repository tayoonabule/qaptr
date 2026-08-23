# Privacy notes

Qaptr captures occasional, downscaled screenshots through a separate macOS helper. Capture is scheduled rather than continuous, and the helper publishes scalar progress separately from image material.

The local review session prepares context on the Mac and applies privacy rules before showing a just-in-time consent boundary. A provider is not invoked until the person approves that boundary. Declining keeps the prepared context local.

Qaptr does not read or store provider credentials for the supported local CLI integrations. The provider CLI owns its own authentication state.

## What Qaptr stores locally

Depending on enabled features, local application support may contain capture bundles, scalar capture progress, control state, onboarding/settings preferences, and a durable history database. Removing that directory removes local history and settings.

## Permissions

The helper may request Screen Recording and Accessibility because it is the process that captures the display and samples application context. Permissions are process- and bundle-specific on macOS. Qaptr reports the helper's live state rather than treating a review-app permission as equivalent.

For an evidence-backed description of what has and has not been verified, read `docs/release.md`.
