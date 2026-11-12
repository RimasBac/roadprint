# RoadPrint feel standard (board, 2026-11-10)

This is the quality bar for every screen and every share card. It applies to all M3+ issues. The CTO checks it in review and rejects a PR that misses a line here, even when CI is green. If a line conflicts with the plan or a mockup, flag it in the issue; don't silently pick one.

**The goal in one sentence:** RoadPrint should feel like an app Apple or Strava could have shipped: quiet, fast, native, with the route as the hero.

## 1. Native first

1. Use system components and behaviours before custom ones: `NavigationStack`, `List`/`ScrollView`, `.sheet`, `.fullScreenCover`, `ShareLink`, `ProgressView`, `Button` with a `ButtonStyle`, system swipe-back and swipe-to-dismiss. A custom control needs a one-line reason in the PR.
2. No custom gesture may break a system gesture (edge swipe back, sheet pull-down, scroll).
3. Every tappable element has a hit area of at least **44×44 pt**, even when the visible glyph is smaller.
4. Respect the safe area and the home indicator on every screen. Bottom buttons sit above the home indicator with at least 8 pt of space.
5. **Two themes: night (dark) and day (light)**, board decision of 2026-11-10 that extends plan §5.1. The app follows the phone's appearance setting. A manual switch (System, Day, Night) comes with Settings in M7; until then the app only follows the system. No view checks the colour scheme to pick a colour: every colour is a night/day pair in the tokens (§2a).
6. iOS 18 is the deployment target (ADR 0002), so use `sensoryFeedback`, `chartXSelection`, `scrollTargetBehavior` and `contentTransition` directly; no back-deployment shims.

## 2. Layout and tokens

All values come from `Design/tokens.json` through the generated Swift constants (AGENTS.md §7.6). **A literal number or hex colour in a view is a review failure.** The token groups below are added by the tokens issue; the Designer may tune them in `tokens.json`, never in Swift.

| Group | Tokens (pt unless stated) |
|---|---|
| `space` | `xs` 4 · `s` 8 · `m` 12 · `l` 16 · `xl` 24 · `xxl` 32 · `screenMargin` 20 (the side margin of every screen) |
| `radius` | `card` 20 · `button` 14 · `chip` 999 (capsule) · `sheet` system default |
| `size` | `buttonHeight` 50 · `minTouch` 44 · `hairline` = 1 device pixel (1 / displayScale) |
| `stroke` | `route` 3 · `routeGlow` 9 · `chartLine` 2 · `areaCircle` 1.5 |
| `motion` | `fast` 0.15 s · `standard` 0.25 s · `slow` 0.40 s · `routeDraw` 0.90 s · spring `response` 0.35, `dampingFraction` 0.85 |
| `opacity` | `regionLabel` 0.35 · `routeGlow` 0.45 · `disabled` 0.4 |

### 2a. The two palettes

One amber family in both themes, as Strava keeps one orange. Only the ground, the text and the way the route is drawn change. The board approved the day palette as warm paper, not pure white. Reference picture: [`Design/reference/board/theme-proof/theme-proof@1300.png`](../../Design/reference/board/theme-proof/theme-proof@1300.png).

| Token | Night | Day |
|---|---|---|
| `background` | `#14161c` | `#f5f3ee` |
| `land` (map ground) | `#1d2029` | `#e9e5db` |
| `card` | `#1d2029` | `#ffffff`, with a hairline `border` |
| `border` | `#30353f` | `#d3cdc0` |
| `text` | `#f0efec` | `#16181d` |
| `textSecondary` | `#a6aab4` | `#5d6470` |
| `route` (line core) | `#ffb547` | `#e8830a` |
| `routeEdge` | not drawn | `#9c4e00` |
| `accentText` (units, kickers, links) | `#ffb547` | `#9c4e00` |
| `buttonPrimary` / its label | `#ffb547` / `#16181d` | the same in both themes |
| `heat.1` … `heat.5` | `#8a4a12` `#c2650f` `#f08c1a` `#ffb547` `#ffe1a0` (more trips = brighter) | `#f3c98b` `#e8a24a` `#d97a12` `#b85c00` `#7a3a00` (more trips = darker) |

How each theme draws:

| Element | Night | Day |
|---|---|---|
| Route | glow (`stroke.routeGlow`, `opacity.routeGlow`, blur 6 pt) under the `route` core | no glow; a `routeEdge` stroke 2.2 pt wider than the core, then the `route` core |
| Area circles | dashed `route` ring, `route` fill at 0.14 | dashed `routeEdge` ring, `route` fill at 0.16 |
| Elevation fill | `route` at 0.50 fading to 0 | `route` at 0.34 fading to 0 |
| Cards | `card` fill, no border | `card` fill with a hairline `border` |
| Secondary button | `card` fill | `card` fill with a hairline `border` |
| Road signs | unchanged: a sign keeps its real colours in both themes | the same |

Share cards are pictures and keep their own fixed look in both themes (Night Highway is always dark, Road Atlas is always paper). Card code uses the fixed night values, never the dynamic ones.

Type scale (derived from mockup 1 at 393 pt width). Every style scales with Dynamic Type through `relativeTo:`.

| Token | Font | Size / weight | Scales relative to | Used for |
|---|---|---|---|---|
| `type.screenTitle` | Inter | 22 Bold | `.title2` | "Trip complete" |
| `type.subtitle` | Inter | 15 Regular | `.subheadline` | date and places line |
| `type.statNumber` | Barlow Condensed | 34 Bold | `.largeTitle` | 649 · 10:52 · 3 |
| `type.statLabel` | Inter | 13 Regular | `.footnote` | "miles", "hours moving" |
| `type.cardTitle` | Inter | 12 SemiBold, tracking 0.8, uppercase | `.caption` | "ELEVATION" |
| `type.body` | Inter | 16 Regular | `.body` | running text |
| `type.button` | Inter | 17 SemiBold | `.headline` | button labels |
| `type.mapLabel` | Inter | 12 Medium | `.caption` | "Salt Lake City area" |
| `type.regionLabel` | Inter | 13 SemiBold, tracking 2.5, uppercase | fixed (it is map art) | "NV" |
| `type.axis` | Inter | 11 Regular | `.caption2` | chart ticks |

## 3. Numbers, units and words

1. Format every number, date and distance with `FormatStyle` for the phone's locale: `1,284,961` in en_US and `1.284.961` in de_DE. Never build number strings by hand.
2. Units follow `UserProfile.unit`. A screen never mixes mi with m, or km with ft.
3. Durations: `10:52` with the label "hours moving" on the summary; `10h 52m` on chips and cards. Under one hour: `0:47` and `47m`.
4. Numbers that change while visible use `.monospacedDigit()` and `.contentTransition(.numericText())`.
5. Copy is plain and calm: sentence case, no exclamation marks, no "Oops", no emoji. Uppercase only where a type token says so.
6. Every string is in `Localizable.xcstrings` with a comment for translators, and plurals use the catalog's plural variants.

## 4. Motion

1. Motion explains a change; it never decorates. Default is the `motion.standard` ease-in-out. Use the spring token for things the finger moves.
2. Nothing animates longer than `motion.slow`, except the one-time route draw (`motion.routeDraw`).
3. **Reduce Motion** on: replace movement and drawing with a `motion.fast` cross-fade. Check `accessibilityReduceMotion` in every animated view.
4. No animation blocks input. Buttons respond on touch-down (pressed state = 0.97 scale and 0.85 opacity, `motion.fast`).
5. 60 fps while scrolling on an iPhone 12-class phone: no blur, shadow or Canvas redraw runs per frame during a scroll. Cache static art as an image.

## 5. Haptics (use `sensoryFeedback`)

| Moment | Feedback |
|---|---|
| Start Trip tapped and recording really started | `.impact(weight: .medium)` |
| End Trip tapped | `.impact(weight: .medium)` |
| Trip summary appears with a saved trip | `.success`, once |
| Scrubbing the elevation chart, each new sample | `.selection` |
| Card style changed in the share picker | `.selection` |
| Share card exported or saved | `.success` |
| An action failed | `.error`, with a visible message |

No other haptics. Never fire one while a trip is recording, apart from Start and End.

## 6. Every screen has four states

Design and build **loading, empty, error and content** for each screen. Maintain automated coverage for applicable states; human/agent image inspection follows the selective policy in §8, not every state on every PR.

- **Loading:** if work takes longer than 300 ms, show a `ProgressView` with one line of text; under 300 ms show nothing (no flash).
- **Empty:** one sentence and one action (for example "No trips yet. Tap Start Trip before you roll.").
- **Error:** what happened, in plain words, and what the driver can do. Never a raw error code, never a dead end.
- Missing data hides its block and the layout closes the gap: no altitude → no chart; no main road → no sign; no badge → no badge card.

## 7. Accessibility

1. Dynamic Type from XS to **AX3**: content scrolls, nothing clips, truncates mid-number or overlaps. The stats row may wrap to two rows from XXL up.
2. VoiceOver: every screen reads in a sensible order; art has one combined label; decorative elements are hidden; buttons have labels and, where useful, hints.
3. Text contrast at least **4.5:1** (3:1 for text of 24 pt and larger). The tokens generator checks the token pairs and fails CI below the limit.
4. Colour is never the only signal (a dotted gap line is also labelled "partially recorded").

## 8. Selective visual review (board, 2026-11-11)

Screenshot generation and image review are separate. Keep automated tests and
artifact capture; do not open every exported image or run extra macOS CI just
to collect duplicate evidence. This section replaces the earlier requirement
for a full visual matrix on every UI PR.

### When review is required

The author labels each UI issue/PR 'Visual review: required' or 'not required'
with one sentence explaining why. The CTO confirms classification in code review.

Review is required once per completed major visual change:
- A new user-facing screen, sheet, share-card style, or redesigned navigation flow.
- A substantial change to layout, primary controls, map/chart rendering, card
  composition, or shared typography, spacing, colours/themes, or fonts.
- A fix for an observed visual defect: inspect only the affected state.
- Changed privacy/safety presentation, such as hidden-route exports,
  recording/error/permission states, or destructive-action confirmation.

Skip image review for internal logic, tests, CI, documentation, data tooling,
or refactoring with no intended visual effect. Small copy/icon substitutions
and local cosmetic tweaks can skip it unless they change layout, legibility,
meaning, or one of the privacy/safety states above. Uncertain impact is
classified by the CTO with a reason, not by screenshot count or lines changed.

### When and who

Batch related implementation PRs into one review of the finished feature,
using an existing successful CI run of the integrated commit. A manual
pre-merge review is reserved for a risky change that cannot reasonably wait.
Designer is the default visual reviewer; CTO may nominate one other agent
with image-viewing capability. The implementer selects evidence; one reviewer
actually opens it. CEO and other agents read the verdict instead of reopening
the same images. Preserve separate board approval where the product plan
requires it (for example icon/card style choices).

A major UI issue stays in_review until the visual verdict is recorded.
A merge or artifact upload alone is not approval. If screenshots or image
tools are unavailable, record 'visual review pending'; never claim inspection.
Do not schedule a new model run merely because another unchanged artifact
appeared.

### Evidence budget

Default: two images; hard initial limit: four selected screenshots/renders
per major feature or coherent shared-style change, not four per PR.
Pick the risks, not the full device x theme x state Cartesian product:
1. Main changed content in its representative screen/theme.
2. Highest-risk alternative (small iPhone with large text, changed error/
   empty/permission state, or other theme).
3-4. Only where the change needs them: other theme for theme/token changes,
   AX3/small-screen layout for typography/layout changes, hidden-route output
   for export/privacy changes, or another affected screen for global styles.

For a new share-card style choose the final export and its worst-case
background/long-label case; include hide-route if affected. Compare against
the approved reference, opening at most one additional reference image.
Do not hide dozens of thumbnails in a contact sheet to evade this budget.
If a global change has more affected surfaces, state which were sampled and
which rely on automated checks. Expand beyond four only for a concrete risk
or detected defect; record the reason and inspect affected surfaces only.

Inspect hierarchy/reference fidelity, clipping/overlap, readable labels and
units, safe areas, theme contrast, and the changed state. Screenshots cannot
prove haptics, animation timing, VoiceOver order, or scrolling performance;
keep those as automated or board-device checks, not visual-pass claims.

### Record and reuse the verdict

Add one short issue/PR comment:
'Visual review: PASS / FIX / PENDING; reviewer; commit SHA; CI run/artifact
link and exact image filenames; states/devices/themes inspected; findings
(or none); untested risks/device checks.'

On FIX, create actionable defects and recheck only the corrected images,
normally one or two. Once PASS exists, reuse it for subsequent nonvisual
commits, citing the reviewed SHA and why changed files cannot affect the
images. A subsequent major visual change or observed regression requires a
new targeted review. Before a TestFlight release the CTO checks these records;
do not repeat the entire screenshot review if the visuals are unchanged.

## 9. Share cards read like a Strava print

1. **The route is the hero.** It is the largest element and nothing overlaps it.
2. **At most three stats.** Each is a small uppercase label above a large Barlow Condensed value. The default three: distance, moving time, highest point.
3. **Generous empty space.** At 1080×1920 keep text and marks inside the safe area (top 220, bottom 320, sides 72 px) so Instagram and TikTok chrome never covers them.
4. **One accent colour per card.** Amber on dark styles. No gradients on text, no outlines on text, no hard drop shadows, no stickers, no emoji.
5. **Legible on any photo.** The overlay style keeps a dark casing under the route and one soft, blurred shadow under the whole card (see the Print reference). It is invisible on dark photos and holds the text on bright ones.
6. **Small, quiet branding:** the ROADPRINT wordmark once, bottom centre.
7. **Honest data.** Cards render only from `TripShareSummary` (AGENTS.md §7b.3). Start and end are approximate; a recording gap is dotted; nothing is invented.
8. Reference: [`Design/reference/board/print-card/`](../../Design/reference/board/print-card/) (the overlay SVG, the generator script and four previews), made by the board from the real I-80 fixture.
