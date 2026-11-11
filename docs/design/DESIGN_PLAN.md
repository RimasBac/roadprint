# RoadPrint visual design plan

Status: approved by the board on 2026-11-10. The Designer owns it from here; changes to the signature, the palettes or the card list need the board.

The visuals are the product. A driver records a trip to get the picture at the end, and the picture is what other drivers see on TikTok. So the bar is not "matches the mockup"; it is "a driver screenshots it without being asked".

## 1. The one idea

**Your road, drawn as one amber line: a line of light at night, a line of ink on the map by day.**

Every RoadPrint picture is the same thing at a different scale.

- **Night theme:** a warm amber line glowing on a near-black ground, like a highway seen from above at night or a long-exposure photo of tail lights.
- **Day theme:** the same line as deep amber ink with a darker edge on warm paper, like a route marked on a road atlas. No glow: glow does not exist on a light ground.
- The app follows the phone's light or dark setting, with a manual switch in Settings, the way Strava does.

The shape, the type, the layout and the accent family are identical in both themes. Only the ground, the text colour and the way the line is drawn change.

- One trip is one line.
- A career is thousands of lines, stacked into a heatmap.
- The app icon is a short piece of the same line.

The test for the whole system: someone scrolling past a RoadPrint card for one second, with the logo covered, should still know what app made it.

## 2. Five rules for every picture

1. **The route is real and it is the hero.** True shape, true borders, true elevation. Drivers know these roads and will spot a fake curve. The route is the largest thing on the picture and nothing covers it.
2. **One big number.** Each picture has a single brag (usually the distance) set very large in Barlow Condensed. Everything else is small and quiet. At most three supporting stats.
3. **Trucking's language, not fitness language.** Road signs, mile markers, atlas pages, odometer numerals, place names. No pace, no heart icons, no medals. We borrow Strava's restraint, not its vocabulary.
4. **Calm, with a lot of empty space, in both themes.** One accent colour (amber). No gradients on text, no outlines on text, no stickers, no emoji.
5. **Honest.** Start and end are approximate circles. A recording gap is dotted. Nothing is invented to look better.

## 2a. What Strava actually does (from its own screenshots, 2026-11-10)

I looked at Strava's press images of dark mode, an older App Store listing in light mode, a light-mode screenshot of the record screen, and a photo of the Instagram sticker in use.

| What I saw | What we take from it |
|---|---|
| The orange accent is the same in light and dark. Only the surfaces and the text flip (near-black and white text; white and near-black text) | One amber family in both themes. Every colour becomes a light/dark pair in `Design/tokens.json` |
| The route is a thin, crisp, solid line in the accent colour. No glow anywhere, in either theme | Our glow is our own signature for night. By day the line is crisp ink, as Strava's is |
| Stats are always a small grey label above a bold value, in a simple grid. Few colours, generous spacing | Same pattern everywhere: label above value |
| The record screen is three huge numerals on a plain ground and nothing else | Confirms the "one big number" rule |
| Charts are an accent line over a soft accent fill, with faint horizontal grid lines only | Same recipe for the elevation chart |
| The Instagram sticker is small and plain: the route trace, the wordmark, three small stats in a row, white, no map | Our Print card can be richer, but it also needs a simple small version, and a dark-ink version for bright photos |

Limits: I could not open Strava's logged-in activity pages, so the light-mode evidence is two screenshots, not a full walk through the app. If you send me screenshots of the screens you like most, I will work from those.

## 2b. The two palettes

| Token | Night | Day |
|---|---|---|
| `background` | `#14161c` | `#f5f3ee` (warm paper, not pure white) |
| `land` (map ground) | `#1d2029` | `#e9e5db` |
| `card` | `#1d2029` | `#ffffff` with a hairline border |
| `border` | `#30353f` | `#d3cdc0` |
| `text` | `#f0efec` | `#16181d` |
| `textSecondary` | `#a6aab4` | `#5d6470` |
| `route` (line core) | `#ffb547` | `#e8830a` |
| `routeEdge` | none (glow instead) | `#9c4e00` |
| `accentText` (units, kickers) | `#ffb547` | `#9c4e00` (amber `#ffb547` fails contrast on a light ground) |
| Primary button | amber `#ffb547` with dark text | the same |
| Heat ramp | dim brown → bright cream (more trips = brighter) | pale amber → deep brown (more trips = darker and thicker) |

These are a first proof, shown in [`Design/reference/board/theme-proof/theme-proof@1300.png`](../../Design/reference/board/theme-proof/theme-proof@1300.png). Before they become tokens I will check every text pair for 4.5:1 contrast.

Share cards keep their own fixed look and do not follow the phone's theme, because a card is a picture: Night Highway is always dark, Road Atlas is always paper. The exception is the Print overlay, which gets a light-ink and a dark-ink version so the driver can match their photo.

## 3. What each piece should look like

### 3.1 The line itself (used everywhere)
The line is a smooth curve, never a jagged polyline, with round ends.

- **Night:** three layers in this order: a wide soft amber glow, a thin dark casing, a solid amber core.
- **Day:** two layers: a darker amber edge and a deep amber core. Crisp, no glow, no shadow.
- **On photos:** the night line plus one soft shadow under the whole card.

The highest point is a small dot, the same dot on the map and on the elevation profile so the eye links them.

### 3.2 Trip summary map (in the app)
A quiet night map: ground `#14161c`, land one step lighter, state and country borders as hairlines, state codes as faint letter-spaced ghost text. The route glows on top. Start and end are dashed amber circles with a place label ("Salt Lake City area"). No pins, no map tiles, no street clutter. When the summary first opens, the line draws itself from start to end once, in under a second.

### 3.3 Share cards (1080 × 1920): five styles with five different ideas
They must not be five colour skins of one layout. Each has its own reason to exist.

| Style | The idea | How it looks |
|---|---|---|
| **Night Highway** (free, the default) | The signature picture. This is the one that spreads, so it gets the most work | The night map fills the top two thirds with the glowing route and state borders. Bottom third: the huge distance number with the unit in amber, the places line, then the road sign and two chips. The badge line appears only when a badge was earned |
| **Print** (free) | A transparent overlay for the driver's own photo of the truck or the view | Header (wordmark, "UTAH → CALIFORNIA", date, road sign), the route, a thin elevation strip, the huge number, three small stats. One soft shadow under everything instead of outlines. Version 2 is drawn |
| **Road Atlas** (Pro) | A page torn from a paper road atlas | Cream paper, a red route line with a darker edge, grey borders, state names in spaced capitals. Atlas details make it: grid letters and numbers along the margins, a scale bar in miles or kilometres, a small north arrow, a faint fold crease. Title and stats strip in dark ink |
| **Poster** (Pro) | A gallery print for the wall | Pure black. The route alone, large, in white, with no map. The road name as a tall typographic title ("I-80 WEST"). The elevation as a solid amber silhouette along the bottom. Almost no other text |
| **Terrain** (Pro) | The land itself | The 3D relief with the route as a glowing ribbon. Already designed and approved (ROA-11); I will not change it |

Shared rules: text and marks stay inside the safe area (top 220, bottom 320, sides 72 px) so Instagram and TikTok buttons never cover them; long place names wrap, then shrink, then truncate; every style has a "hide route" version with places and stats only.

### 3.4 The heatmap (the long-term hero)
It should look like a night satellite photo of one driver's career. Roads driven once are thin and dim; roads driven fifteen times are thick and almost white-hot. Where lanes overlap, the light adds up, so home terminals and regular hubs glow like cities. Borders are faint; there is no other map detail. The five-step amber ramp from the plan stays. Free shows the last 30 days; Pro shows everything, and the difference between the two should be visible at a glance (a few lines versus a web).

### 3.5 Road signs
A driver from that country must recognise the sign at 32 px, at a glance. That means real proportions, not "a green rectangle". Each sign is redrawn from the real sign's shape, which I will check against the official drawings before finalising. The number is live text in Barlow Condensed, a typeface modelled on highway signage, so it sits naturally in every sign.

| Sign | How it should look |
|---|---|
| US interstate | The red, white and blue shield with the "INTERSTATE" band; a wide version for three digits; a plain-band version under 40 px |
| US highway | The white six-point shield with a black keyline, readable on both dark and paper backgrounds |
| Canada | A white shield with a green top, in the Trans-Canada style, without provincial crests |
| E-road | A green plate, white border, white number |
| UK motorway / A-road | A blue plate with a white number; a green plate with a yellow number |
| Australia | A green plate with a gold number for alphanumeric routes, and the green-and-gold shield for national highways |
| Generic | A neutral plate in the app's own colours, for everywhere else |

### 3.6 Later pieces (direction only)
- **Badges (M7):** enamel-pin look, one shape per family (hexagon for legendary roads, shield for countries, mile marker for milestones), amber on dark.
- **App icon:** a short glowing amber line bending across a dark tile.
- **App Store screenshots:** real cards on a dark ground with one line of text each.

## 4. Where the drafts stand, honestly

| Piece | State | What is wrong with it |
|---|---|---|
| Print card v1 | Rejected | Flat centred text stack, small route, no identity |
| Print card v2 | Good draft | Small labels are weak on a very bright sky; no hide-route, tall-route or kilometre versions yet |
| Road signs, first sheet | Rough | Only the interstate shield is recognisable. The US highway shield is a blob and loses its outline on dark. Canada is bland. The UK A-road and Australia signs look the same. The rectangular plates are generic |
| Night Highway, Road Atlas, Poster | Mockup only | The mockup shows the idea but not production quality: glow, spacing and type need a real pass |
| Heatmap | Mockup only | No look study on real multi-trip data yet |

## 5. How I will work and how we judge

1. **Three real routes for everything:** I-80 Salt Lake City → Sacramento (USA, miles), Kaunas → Verona over the Brenner (Europe, kilometres, long names), Perth → Adelaide across the Nullarbor (Australia, nearly straight).
2. **Real rendering:** every draft is rendered with the app's actual fonts, never judged from the code.
3. **Four checks per picture:** full size; thumbnail at 25 % (the size in a share sheet); on a dark photo and on a bright photo; next to the mockup.
4. **Contact sheets to you at each step.** You approve the look before any agent builds it. Taste decisions are yours.
5. **Then it becomes a task:** the approved drawing, its numbers as design tokens, and its edge cases go into the agent's task, so the build matches what you approved.

## 6. Order of work

1. **Night Highway card** to final quality on the three routes. It is the free default and the picture that spreads.
2. **Road signs** redrawn to recognisable quality, with a contact sheet on dark and paper.
3. **Print card** variants: hide route, tall route, kilometres.
4. **Road Atlas** and **Poster** cards.
5. **Heatmap** look study from sample trips.

Steps 1 and 2 come first because the trip summary screen (M3) and the first share card (M4) depend on them.

## 7. Decisions (all answered by the board on 2026-11-10)

1. **Signature:** "a line of light on the night" is approved, with a day theme added. The day theme is warm paper, not pure white.
2. **Region:** the USA gets the polish first. Europe and Australia follow.
3. **Print card:** it is the fifth card style and it is free.
4. **Today's goal:** the first test on a phone. Anything that does not help that waits.

Open product decisions about screens and popups are listed in [`SCREENS.md`](SCREENS.md) §6.
