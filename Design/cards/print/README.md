# Print share card (free)

The fifth card style (plan §4.4): a **transparent overlay** the driver drops on their own photo, like an activity sticker. It is built from the board's v2 reference (`Design/reference/board/print-card/`, ROA-57). Export is 1080×1920 px, sRGB, **transparent background**.

All values live in [`Design/tokens.json`](../../tokens.json) under `print.*`. The SVGs and previews are generated from them by `Tools/design/print-card.mjs`. If a file disagrees with the tokens, the tokens win. Every size below is in export pixels.

## Files

| File | What it is |
|---|---|
| `print-card.svg` | The card for the real I-80 trip: the layer order, every slot and the placeholder text the app fills (`<text>` elements with ids such as `title`, `date`, `distance`, `stat-1-value`) |
| `print-card-hide-route.svg` | "Hide route on card": the two places and the stats only |
| `previews/<route>-<background>.png` | I-80, Brenner and Nullarbor on `transparent` (checkerboard), `dark` (`#14161c`), `sky` (a bright photo: blue sky and white cumulus) and `night` (a night photo: Milky Way, town glow, rock silhouettes) |
| `previews/<case>.png` | Edge cases on app dark with the safe area (blue) and the route box (pink) |
| `previews/contact-sheet.png` | I-80 first at 50 % on the four backgrounds, then every preview at 25 % (270×480, the size of a share-sheet thumbnail) |
| `previews/checks.json` | Glyph-local text contrast and route contrast on both photos, per text element, with the method (see "Legibility on photos") |

The two photos are real photographs, used **only in the previews**, never in the card SVGs: a CC0 sky and a public-domain night photo, with source and licence in `Tools/design/fixtures/photos/README.md`. Brenner and Nullarbor geometry: OSRM over OpenStreetMap (© OSM contributors, ODbL), privacy-trimmed and with altitude from AWS Terrain Tiles, saved in `Tools/design/fixtures/print-routes.json` for previews only. I-80: the core test fixture with the mockup's `elev.json`.

## Layer order (bottom to top)

1. *(transparent: nothing; the photo is the background)*
2. **Soft shadow** (`print.shadow`): the whole card (`#art`) drawn once more underneath in `print.color.ink`, as two passes merged:
   - wide: blur 9, moved down 3, 62 %;
   - tight: spread 5, blur 3, moved down 1.5, 90 %.

   It disappears on dark photos and holds text on bright ones. There are no outlines on any text.
3. **Route glow**: amber, 30 px, 55 %, blur 16.
4. **Elevation fill**: an amber gradient from 50 % to 0, drawn above the shadow so the shadow never greys it.
5. **The art**:
   - wordmark, title (arrow drawn as a path), date and road sign;
   - route casing (ink, 17 px, 50 %) and the amber core (11 px), with round caps and joins;
   - recording gaps as dots;
   - start and end rings, the highest-point dot and the area labels;
   - the elevation line with its casing, the dot and its label;
   - the big number with its unit;
   - the hairline and the stats.

### How the app draws it natively (no SVG filters ship)

- **Glow**: stroke the route path in amber at 55 % with width 30, then apply a Gaussian blur of radius 16 (`GraphicsContext` with `.blur(radius:)` in a layer, or `CIGaussianBlur`). Then stroke the casing and the core unblurred on top.
- **Soft shadow**: render the art layer once into an offscreen layer and use its alpha as a mask filled with `print.color.ink`. Draw that mask twice:
  - **wide**: blur 9, offset y 3, opacity 0.62;
  - **tight**: first grow the mask by 5 px (a morphology max, `CIMorphologyMaximum`, or stroke every glyph and path 10 px wide in ink), then blur 3, offset y 1.5, opacity 0.9.

  Then draw the art on top. Composite in **sRGB**. In linear light the ink turns grey and makes a light ring around the text on dark photos.
- **Elevation fill**: a plain linear gradient. It is not a filter.

## Layout rules

The reference layout is kept as specified in the issue. These rules cover what the reference did not:

| Case | Rule | Preview |
|---|---|---|
| Route shape | The route is fitted into the **wide box** (118–962 × 480–830) or the **tall box** (520×430, centred in the same band), whichever draws it larger (the tall box needs to be at least 5 % larger to win). North–south trips such as Brenner get the tall box | `brenner-*` |
| Nearly straight route | Fitted by width and centred vertically. Nothing special | `nullarbor-*` |
| Short trip (12 km) | Same fitting, so the route is magnified. One region → the title shows the two area names | `short-12km` |
| Recording gap | The route and the elevation line break; the missing part is a straight row of round dots, `textSecondary`, 7 px every 16 px | `recording-gap` |
| No altitude | No elevation strip and no highest-point dot. The route box grows down to 1105 | `no-altitude` |
| No career distance entered | The third stat becomes **HIGHEST POINT** (for example "7,102 ft"). With no altitude either, the row has two columns | `no-career`, `no-career-no-altitude` |
| Long place names | One line `A → B` if it fits left of the road sign. Otherwise two lines: `A`, then `→ B`, both at one size. That size shrinks to 80 % (`fitMinScale`), and below that the text gets an ellipsis. Line height 96, so umlauts clear line 1. The date and the route box move down with the second line | `long-names`, `longer-names` |
| Area labels | Ring centre + 48 px, tried at 8 spots (outward first). A label slides along the safe edge rather than past it and keeps 14 px from every other mark. Long names: 380 px wide, then 80 %, then an ellipsis | all |
| Highest-point label | Above the strip dot on the side with room, else beside the dot. It never overlaps the ELEVATION kicker | `km-de_DE` |
| Elevation direction | The strip runs in the same direction as the route on the map (mirrored when the route ends to the left), so the peak in the strip sits under the peak on the map | `i80-*` |
| Big number | Shrinks (down to 72 %) only when number + unit would pass the right safe edge | |
| Units and locale | Distance unit, number format, labels and dates come from the locale: `1.197 KM`, `12 Std. 40 Min.`, `KARRIERE-KM` | `km-de_DE` |
| Hide route | No route, no elevation strip (it would show the route's shape). The two rings sit at the **city centres** of the named places, joined by a faint dotted line that says "not the route" | `hide-route` |

## Checks (run by the generator)

- **Safe area** (top 220, bottom 320, sides 72): every text box (the ink box, measured with the renderer and the real fonts) and every mark, including round stroke caps, must be inside. There are **no exceptions**: the big number and each title line are placed so their ink starts exactly on the 72 px edge (a "1" sits further right in its advance than a "6", so the x is computed per string). The generator fails otherwise, and every edge-case preview shows the guides.
- **Collisions**: no label may touch the route, a ring or the highest-point dot, and no two labels may overlap. All 12 cases pass.
- **Legibility on photos** (`previews/checks.json`; I-80, Brenner, Nullarbor and `longer-names` on both photos). The generator **fails** if any text element is below the threshold.
  - **Background**: the card is rendered on the photo with every `<text>` hidden, so the shadow and glow stay. That is the local background.
  - **Glyph mask**: the same text is rendered white on black, with no shadow and the same antialiasing.
  - **Antialiasing policy**: a pixel with mask coverage ≥ 0.75 is *glyph*; its colour is the text fill composited over the pixel behind it (area labels have 90 % fill opacity). Pixels with lower coverage are edge blends of text and background, so they are not counted as glyph. The *surround* is every pixel with coverage < 0.02 within 3 px of a glyph pixel, which is what the eye sees right next to the stroke.
  - **Rule**: for each text element, at least **98 %** of its glyph pixels (against the background under them) and 98 % of its surround pixels must reach **3:1** (WCAG 2 formula). The road sign is excluded because it has its own opaque panel.
  - **Result**: all text passes on both photos. The worst element is the amber wordmark on the sky: 99.7 % of its surround pixels are at 3:1 or better, and its 2nd percentile is 3.34:1. On the night photo the worst 2nd percentile is 5.5:1.
  - **Route**: the amber core is compared with the darkest pixel 8–14 px outside it on each side (casing and shadow). The median is 6.9–7.4:1 on the sky and 7.4–7.7:1 on the night photo. The share at 3:1 or better is 92–100 %. The lowest is Nullarbor, where its long straight line crosses white cloud under its own glow (`nullarbor-sky.png`); this is reported, not enforced.
- **25 % scale**: the contact sheet is made of 270×480 thumbnails. The number, the title and the route read at that size; the small labels become texture, as intended.

## Changes from the board's reference (for the board's review)

- **Shadow:** the tight spread pass is new. With the reference's shadow alone, small labels on white cloud measured 1.0–2.5:1, so this fixes the weakness the board noted. After the CTO review it is 90 % with a 5 px spread (was 75 %, 4 px): at 75 % the amber wordmark failed the glyph-local check on the sky photo (only 76 % of its surround at 3:1).
- **Shadow colour space:** the shadow is composited in sRGB. The reference's filter ran in linearRGB, so its ink turned grey (a light ring around the text on dark photos).
- **Route casing:** 50 % instead of 30 %, for the route edge on bright sky.
- **Title line height:** 96 instead of 88. The arrow goes to line 2 when the title wraps.
- **Elevation strip:** it follows the map's direction.
- **Highest point:** it reads the highest recorded point of the trip (7,102 ft on I-80), not the mockup's profile maximum (7,139 ft).
- **Road sign:** drawn from the production templates in `Design/road-signs/` (PR #26).

## Regenerate

```bash
cd Tools/design && npm install && npm run fonts
node print-card.mjs
```
