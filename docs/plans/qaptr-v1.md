---
title: Qaptr v1
artifact_readiness: requirements-only
status: draft
created: 2026-08-14
ambiguity: 0.042
ambiguity_threshold: 0.05
threshold_source: user request
platform: Apple-silicon macOS
---

# Qaptr v1

## Product contract

Qaptr is an exceptionally lightweight, privacy-first macOS menu-bar app that periodically captures sparse visual and contextual snapshots of a person's work. When the person opens Qaptr, the full app processes recent captures through their chosen AI provider and presents a few concise observations about time use, repeated workflows, and automation opportunities.

The product should normally feel invisible. Its opened experience should be beautifully simple, fast, monochrome, and native-feeling, with the interaction quality of Apple or Linear and the visual ambition of Shopify Design.

## Primary outcome

Help a person recognize work they repeat, inspect a promising workflow at greater detail, and receive a polished Markdown brief explaining how that workflow could be automated.

## Core interaction

1. Qaptr runs as a lightweight menu-bar capture helper.
2. In sparse mode, it captures selected displays once every 10 minutes.
3. At capture time, it samples lightweight context such as active app, window title, browser URL, document name, display, idle state, and temporary visible Accessibility text/structure.
4. It never records clipboard contents, raw keystrokes, or continuous Accessibility activity.
5. Opening Qaptr starts local preparation and provider-backed analysis of recent captures. No OCR or AI analysis runs in the background helper.
6. The first screen presents a small number of smart observations combining chronological time use, repeated workflows, and automation potential.
7. A person can select an observation and choose **Qaptr in more detail**.
8. Qaptr recommends an appropriate detailed-capture interval and explains it simply.
9. Detailed capture continues until the person explicitly stops it. A subtle persistent menu-bar state makes enhanced capture visible.
10. After analysis, Qaptr can generate a polished Markdown automation brief. It does not launch agents, create workflows, or execute automations.

## Capture requirements

- Sparse default: one capture every 10 minutes.
- Multi-display changes are handled silently.
- Settings provide a minimal display selector for one or multiple displays.
- High-resolution captures are downscaled before caching to reduce memory, disk, and provider costs.
- Capture and metadata sampling happen only at the scheduled instant rather than through continuous observers.
- The background capture process must remain below 50 MB resident memory under normal operation.
- The opened app should remain below 150 MB resident memory during ordinary analysis and review flows.

## Privacy contract

- Screenshots are temporary processing material, not durable history.
- The person chooses a simple cache lifetime.
- Expired screenshots are permanently deleted.
- Durable history contains only compact workflow summaries and observations, never screenshot thumbnails.
- OCR and PII redaction occur locally before any provider receives an image or extracted context.
- Images that cannot be confidently redacted fail closed and are excluded from provider requests.
- Exclusions are communicated quietly, for example: “1 capture was excluded because it could not be safely redacted.”
- Qaptr clearly explains that approved redacted data is sent only to the person's selected existing AI provider.
- Provider credentials use secure operating-system storage.

## Provider contract

- OpenRouter is built in as a bring-your-own-key option with a minimal key-entry experience.
- Qaptr detects compatible installed agent CLIs where feasible.
- Target integrations include Codex, Hermes, OpenClaw, Claude, OpenCode, and Jcode.
- Provider capability differences must be hidden behind a stable adapter boundary.
- Unsupported or incompatible detected tools must never appear as working choices.
- Provider output is normalized into Qaptr's observation and Markdown-brief formats.

## Desktop experience

- The menu-bar helper is quiet, low-memory, and legible at a glance.
- The main app opens directly into recent observations rather than a dashboard full of controls.
- The interface follows system light and dark appearance, using predominantly whites, blacks, and disciplined neutral tones.
- Typography, spacing, motion, icons, loading, empty, permission, and failure states receive production-level design attention.
- Settings remain intentionally small: capture cadence/profile, displays, cache duration, provider, and privacy/permission status.
- Onboarding stages macOS permissions, display selection, capture explanation, provider selection, and privacy consent without overwhelming the person.

## Website

- Build a separate public Qaptr website whose primary conversion goal is joining a waitlist.
- Use Shopify Design as a quality reference, not a template to copy.
- Favor expressive editorial composition, exceptional typography, purposeful motion, strong art direction, and near-monochrome restraint.
- Avoid generic SaaS card grids, AI gradients, decorative glassmorphism, and templated landing-page structure.
- The site must be responsive, accessible, fast, and respectful of reduced-motion preferences.

## Platform and portability

- v1 supports Apple-silicon macOS.
- The core should be Rust-first.
- Tauri is acceptable for the opened application if it best satisfies quality and memory constraints.
- Platform-specific capture, OCR, credential, accessibility, and permission implementations must sit behind replaceable interfaces.
- Later Windows and Linux support should require new platform adapters rather than a rewrite of workflow, storage, provider, or analysis logic.

## Explicit non-goals for v1

- Windows or Linux release.
- Cloud account system or Qaptr-managed AI credits.
- Continuous screen video recording.
- Clipboard capture, keystroke logging, or continuous Accessibility monitoring.
- Background OCR or provider analysis.
- Retaining raw screenshots or redacted thumbnails as durable history.
- Automatically creating, launching, or executing automations.
- Team collaboration, cloud sync, or shared workflow libraries.

## Acceptance criteria

1. The helper captures selected displays on schedule while remaining below 50 MB RAM in a representative long-running test.
2. Opening Qaptr analyzes the recent cache without requiring the helper to have performed OCR or AI work.
3. Local redaction removes supported PII classes and excludes every low-confidence image before provider handoff.
4. The app communicates excluded images without blocking analysis of safe captures.
5. A user can move from an observation to **Qaptr in more detail**, accept a recommended profile, see that enhanced capture is active, and stop it manually.
6. Raw captures expire according to the configured cache lifetime while summaries remain available.
7. At least OpenRouter and one installed CLI adapter complete the end-to-end observation flow in v1.
8. Qaptr produces a useful, well-formatted Markdown automation brief from a selected repeated workflow.
9. The opened app remains below 150 MB RAM in representative ordinary-use tests.
10. Onboarding successfully guides a fresh macOS user through required permissions and provider configuration.
11. The website presents Qaptr clearly and submits a waitlist signup through a production-ready endpoint.
12. Both app and website pass keyboard, contrast, reduced-motion, loading, empty, and error-state checks.

## Pending planning research

Architecture, redaction technology, provider feasibility, implementation sequencing, and measurable benchmark methodology will be added after the planning swarm reports.
