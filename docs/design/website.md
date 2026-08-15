# Website design rationale (U21)

This records what was studied at <https://shopify.design/> before any markup was
written, which specific decisions the Qaptr waitlist site matches, and which
choices were deliberately rejected. Reviewed live with Playwright (Chromium,
1440×900) on 2026-08-14: full-page screenshot, ten scroll-position captures,
and computed-style/DOM inspection of typography, color, and motion.

## What was observed on shopify.design

- **Type as the primary graphic device.** The hero headline ("Make the new
  normal") renders at 220px in a serif display face (`AntiqueLegacy`), weight
  500, with aggressive negative tracking (`-8.8px` letter-spacing, effectively
  around -4% of the point size) and tight leading (154px line-height on a
  220px face, well under 1x). The type itself is the hero image — there is no
  photograph, illustration, or gradient behind it. Body copy uses the same
  serif at 20px with a much smaller negative tracking (-0.4px), so the display
  and body sizes read as one typographic family rather than a display face
  paired with an unrelated UI font.
- **A second, deliberately utilitarian face for metadata.** Small caps-style
  labels ("LIVE", section eyebrows) use `FragmentMono`, a monospace face, at
  14px with uppercase transform and +0.7px tracking. This is the only place
  tracking goes positive. The contrast between the humanist serif (voice) and
  the mono (system/status) is a structural device repeated everywhere: display
  type speaks, monospace labels report.
- **Near-monochrome base with one saturated accent per module, never blended.**
  The page shell is pure black on white. Individual case-study tiles and
  section backgrounds each carry exactly one saturated color (lime `#BFFF04`,
  orange `#FE432A`, cobalt `#0225AC`, pink `#FFAAC7`, deep plum, forest green),
  used as a flat fill, never a gradient and never mixed with a second accent
  in the same module. Color is a section-identity marker, not a decorative
  layer over the whole page.
- **A single literal, sculptural data visualization for the one number that
  matters.** The "every 26 seconds" merchant-sale stat is not a stat card. It
  is a full-viewport orange clock hand sweeping across a huge outlined "26",
  built as canvas/SVG, scroll-driven. One number gets one dramatic treatment
  rather than a row of small stat tiles.
- **Editorial masonry for case studies, not equal-height cards.** The "Building
  Artifact" / project wall uses an asymmetric grid: tall dark tiles next to
  short pastel ones, mixed aspect ratios, real product photography and UI
  captures, no shared card chrome (no shadow, no border, no rounded-card
  template look). It reads as a cut-and-paste editorial spread, not a
  generated card grid.
- **Marquee and motion are small, purposeful accents.** The one moving element
  in the primary viewport is a small pill button whose label loops
  ("apply · apply · apply · now") via a 48s linear CSS animation
  (`transform: translateX`), not a decorative hero animation. Scroll reveals
  are present but modest — content appears, it does not fly in.
- **A plain, low-chrome header and footer.** The header is a logo mark, one
  pill CTA, and nothing else. The footer is a hairline rule, a wordmark row,
  and one more CTA pairing. No mega-footer, no sitemap column dump.

## What Qaptr matches

- **Type as the hero, no photography or gradient behind the headline.** The
  landing headline is set at fluid clamp() sizes reaching roughly 9–11rem on
  desktop, in a serif display face, with negative tracking and tight leading,
  exactly the compositional move that gives shopify.design its authority. No
  device mockup, no gradient orb sits behind it.
- **Two-voice type system: serif for editorial voice, mono for status/meta.**
  Qaptr's display and body copy use a serif (system-stack fallback to avoid a
  paid-font dependency: `"New York", ui-serif, Georgia, serif` at build time,
  swappable for a licensed face later without touching structure). Labels,
  the waitlist count, the form's status line, and timestamps use a monospace
  stack (`ui-monospace, "SF Mono", Menlo, monospace`), uppercase, with
  positive tracking. This mirrors the "voice vs. report" contrast directly.
- **Near-monochrome page with exactly one accent color used once.** The page
  is black-on-white (dark-mode inverts to white-on-near-black). Qaptr's single
  accent is a warm signal amber, used only for the capture-interval motif (an
  arc/dial diagram, described below) and the focus ring. It never appears as
  a background fill, a button color, or a gradient stop.
- **One literal, sculptural diagram instead of a feature-icon row.** In place
  of a three-icon "how it works" grid, Qaptr renders a single large arc dial
  (inline SVG, no canvas/WebGL) that shows the configurable 5–300 second
  capture interval, echoing the compositional idea of shopify.design's
  26-second dial: one number, one honest picture, full width, no card around it.
- **Editorial rag instead of a card grid for the body sections.** The three
  content sections (what it captures, what it never captures, how the
  workflow document is used) are set as wide asymmetric text columns with a
  pulled quote-scale statement per section, not three equal cards in a row —
  matching the masonry wall's refusal of equal-height chrome without copying
  its specific tile content.
- **A single small looping label, not a hero animation.** The waitlist button
  has a subtle `background-position` sheen loop under 3s only when motion is
  not reduced, matching the scale and restraint of the "apply" marquee without
  reusing marquee text-looping (Qaptr's is a static label; only a thin light
  sweep moves, and only on the primary CTA).
- **Minimal header, minimal footer.** Header is wordmark plus one CTA button
  that jumps to the form. Footer is a hairline rule, wordmark, and a privacy
  line — no link farm.

## What Qaptr deliberately does not copy

- **No WebGL canvas scene, no 3D-rendered hero objects.** shopify.design
  loads a full WebGL background scene and multiple 3D-rendered objects
  (capsule shapes, product renders) purely for atmosphere. That is
  incompatible with the 250 KB transferred-byte and 1800 ms LCP budgets here,
  and the product itself is not visual/physical, so it would be decoration
  without meaning. Qaptr uses only inline SVG and CSS.
- **No masonry case-study wall or product photography.** Qaptr has no
  portfolio of shipped work to display, so reproducing the asymmetric project
  grid would be a template, not a matched craft decision. Qaptr does not
  include a case-study section at all.
- **No multi-color-per-viewport palette.** shopify.design cycles through five
  or six saturated section colors across its length. Qaptr is a single
  one-page waitlist, so it uses exactly one accent, once, to avoid reading as
  a color-swatch demo on a much shorter page.
- **No text-loop marquee, no drag-to-reorder toy interactions.** The site
  includes a draggable Alice-in-Wonderland text toy and other one-off
  interaction Easter eggs. Those are appropriate for a portfolio meant to be
  explored; they are noise on a conversion-focused waitlist page and would
  cost motion and script budget for no acquisition value.
- **No custom licensed display/mono font files.** `AntiqueLegacy` and
  `FragmentMono` are Shopify's licensed faces. Qaptr uses system serif and
  monospace stacks so there is no font-loading cost against the 250 KB budget
  and no licensing dependency; the compositional lesson (serif voice + mono
  report) is matched, the specific typefaces are not.
- **No generic SaaS patterns regardless of source.** Independent of the
  reference site, R-W4 rules out card grids, AI-style gradients, and
  glassmorphism outright; none appear anywhere in this design.

## Layout, in order

1. **Header** — wordmark, "Join the waitlist" pill link (anchor to `#join`,
   no JS required).
2. **Hero** — eyebrow mono label ("PRIVATE BETA · MACOS"), huge serif
   headline ("Qaptr keeps the ten minutes you forget you spent."), one-line
   serif subhead, and the inline email form (server-rendered, no-JS
   functional) directly under the fold — the primary conversion action is
   visible without scrolling on a laptop viewport.
3. **Arc diagram section** — the 5–300 second capture-interval dial, full width,
   amber accent, with a two-sentence caption in mono.
4. **Three editorial passages** — "What it captures" / "What it never
   captures" / "What it becomes," each a wide asymmetric text block with one
   pulled statement set large, no card chrome.
5. **Second form placement (`#join`)** — repeats the same server-rendered
   form as a closing call to action, so a scrolled reader does not have to
   scroll back up.
6. **Footer** — hairline rule, wordmark, privacy one-liner, year.

## Motion

- Scroll-in fade/translate of 8px over 240ms on section entry, implemented
  with CSS `@starting-style`/`transition` plus a small `IntersectionObserver`
  progressive enhancement; content is fully visible with no script at all.
- The arc dial's needle animates from the shortest to longest interval position once, on
  first scroll into view, over 900ms, `ease-out`.
- The CTA button has a 2.4s `background-position` sheen loop.
- Every animation is wrapped so `prefers-reduced-motion: reduce` disables the
  sheen loop, the needle sweep (rendered in its end state instead), and the
  scroll-fade (content renders at full opacity/position immediately).

## Accessibility and performance commitments

- Contrast: body text is `#111` on `#fff` (and `#f2f2f2` on `#0a0a0a` in dark
  mode), both exceeding WCAG AA for normal text; the amber accent is used
  only for decorative strokes and a focus ring, never as text-on-background
  contrast-bearing content.
- Full keyboard operability: header link, both form inputs, both submit
  buttons, and the footer link are all native interactive elements in source
  order with visible focus rings; no custom widgets, no keyboard traps.
- No client JavaScript is required for the primary conversion action: the
  form is a plain HTML `<form method="post">` posting to
  `/api/waitlist`, which redirects back to a confirmation state server-side.
  JS only adds the optional scroll-fade and needle animation as progressive
  enhancement.
- Budget: no web fonts, no images beyond inline SVG, no client framework
  runtime shipped (Astro islands are not used; the page has zero hydrated
  components). Measured numbers are recorded in the report delivered with
  this unit and re-verified by `npm run build` output size and the Lighthouse
  throttled-mobile trace in `web/tests/`.
