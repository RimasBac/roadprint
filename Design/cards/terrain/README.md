# Terrain share card (Pro): style 5

The 3D card: the land around the trip, in perspective, filling the whole card, with the route as a glowing amber ribbon at its recorded altitude. Export is 1080×1920 px, sRGB.

**Status: accepted by the board (2026-11-24).** The board approved style 3 on 2026-11-09 ([ROA-11](/ROA/issues/ROA-11)). On 2026-11-24 it reviewed style 4 and asked for the relief to fill the whole screen and to stop looking cheap; style 5 is the answer, chosen by the board over a satellite mock-up. Style 5 needs finer elevation than the 2′ bundle of ADR 0001: see [ADR 0006](../../../docs/adr/0006-terrain-elevation-tiles.md).

All values live in [`Design/tokens.json`](../../tokens.json) under `terrain.*` (`recipeVersion` `terrain-style-5`). If a file disagrees with the tokens, the tokens win. Every size is in export pixels.

## What changed from style 3

| | Style 3 (approved 2026-11-09) | Style 5 |
|---|---|---|
| Frame | Relief in a faded box in the middle (y 380–1280) | Full bleed: land from a horizon at y 150 to below the bottom edge |
| Camera | Orthographic, 34° | Perspective (`camera.perspective` 1.6: the far edge at 1/2.6 scale), 36° |
| Detail | 2′ grid (~3.7 km), 240×240 mesh, flat triangles ~4.5 px | Elevation at the mesh spacing (z6–z11, 2 km to 100 m), 820×700 mesh, triangles ~2 px |
| Light | Neutral Lambert | Golden hour: warm key `#ffd9a8` from 300° at 24°, cool sky fill `#6d7fa8` in the shadows |
| Route framing | Route padded into the box | Route framed in a middle band (y 640–1150); title and number sit on open land |
| Ribbon | On the ground, 8 px | Lifted 7 px with a soft ground shadow, 9 px |
| Labels | Dark plates | No plates: one soft ink shadow (`terrain.textShadow`) under all type, plus scrims |
| Number | 220 px | 280 px |

## Files

| File | What it is |
|---|---|
| `terrain-card.svg` | Editable template: the layer order, every slot and the placeholder text. `#relief-slot` stands for the relief the app paints |
| `terrain-card-hide-route.svg` | Template for "Hide route on card": the two places and the stats only |
| `previews/*.png` | 1080×1920 previews (below) and `contact-sheet.png`. Each carries a stamp with its elevation source; the stamp is never part of the card |

## Layer order (bottom to top)

1. `#background` `#14161c`
2. `#relief`: the full card. The core paints the mesh far to near, one flat colour per triangle (ADR 0006 point 7)
3. `#scrim-top` (background colour, 60 % at y 0 → 0 at y 620) and `#scrim-bottom` (0 at y 1120 → 85 % at the bottom). They hold the type over bright land
4. Ribbon:
   1. `ribbon-occluded`: amber at 55 %, 4 px, dash 12/10, on the ground
   2. `ribbon-gap`: grey `#a6aab4` dots, 5 px, round caps every 13 px, on the ground
   3. `ribbon-shadow`: black at 70 %, 14 px, blur 4, on the ground track
   4. Lifted 7 px (`ribbon.lift`): glow 0 (14 px, blur 6, 75 %), glow 1 (30 px, blur 24, 40 %), casing (`#14161c`, 14 px, 85 %), core (amber, 9 px)
5. `#route-ends`: approximate start and end circles (r 16, 3 px stroke, 18 % fill), lifted with the ribbon
6. `#summit`: marker (r 9 `#f0efec`, 4 px background ring), a vertical leader (2 px, 85 %, 120 px) and three lines of text with the text shadow
7. `#type`: date kicker, title, number with unit, road sign and chips, all with the text shadow

## Relief look

Each step is plain per-vertex maths, so it belongs in `RoadPrintCore` and ports to Android as is. `Tools/design/terrain_relief.py` is the readable reference.

1. **Framing.** Ground depth runs d = 0 (near, below the card) to 1 (horizon); scale is f(d) = 1/(1 + p·d). Screen y of the ground is `nearY − (nearY − horizonY)·ln(1 + p·d)/ln(1 + p)`. The footprint grows until the route (with `routePadding`) fits both the band (`routeBandTop..routeBandBottom`) and the safe width, and the near edge is at least 60 km wide.
2. **Mesh.** Rows evenly spaced on screen from below the card to the horizon (820 rows), 700 columns, each row as wide as the card at its depth plus 60 px bleed. So triangles are about 2 px everywhere, near or far.
3. **Elevation** at the vertices from Terrarium tiles at the zoom whose pixel is closest to the column spacing, within a 160-tile budget, lightly smoothed (σ 0.8 px) against aliasing in far rows.
4. **Ground colour** (`terrain.landCover`): Natural Earth I land cover, graded for the dark card (saturation 1.6, gamma 1.35, brightness 0.64). **Snow** above 2,600 m blends to `#f0efec`, fully by 3,300 m. **Water** `#15212e`, blended across the coast.
5. **Light** (`terrain.hillshade`): `ambient · ambientColor/max + diffuse · max(0, n·L) · keyColor`, capped at 1.4, multiplied into the ground colour. Normals come from the elevation grid itself.
6. **Occlusion** (`terrain.occlusion`): `1 + 2.6·(h − gaussian(h, 4 km))/span`, clamped to 0.5–1.15. Valleys darken, ridges lift.
7. **Route light** (`terrain.routeLight`): heat-ramp `#c2650f` around the route, a 26 px gaussian at 0.35. Not in hide-route mode.
8. **Haze** toward the horizon (`#211f29`, 0.55·d^1.8), and the last 8 % of the depth melts into the dusk band (`terrain.sky`).
9. **Exaggeration**: unchanged rule, 1.5–10×.

### Ribbon rules (ADR 0001, unchanged)

- **Visible:** glow, casing and core at the *recorded* altitude, lifted 7 px with its shadow on the ground track.
- **Occluded:** terrain between the point and the camera rises more than `depthBias` (10 px) above the sight line: x-ray dash on the ground, no glow.
- **Gap:** a recording gap or invalid altitude: a straight dotted link, never interpolated, never glowing.

### Summit label placement

Above the marker on the open side (towards the card centre), then above on the other side, then below on both sides, then the same with the leader ×1.5 and ×2. The first placement that stays inside the side safe area and near the route band (from 150 px above it to 40 px below it), and doesn't cover the ribbon, wins. The kicker is "Highest recorded point"; the name line appears only when trusted offline enrichment provides a name.

## Text slots

| id | Style token | Notes |
|---|---|---|
| `kicker-date` | `type.kicker` | Upper case, localized long date |
| `title-line-1/2` | `type.title` | "From → To", at most 2 lines, wrap at the arrow |
| `summit-kicker/value/name` | `type.summit*` | Value in the user's unit. The name is optional |
| `stat-number`, `stat-unit` | `type.number` (280), `type.unit` (80) | Unit x = number advance + 18 |
| `stat-chip-n` | `type.chip` | Height 72, radius 36, padding 28, gap 16. "Elevation unavailable" is the last chip when it applies |
| `road-sign` | n/a | 72 px. Fill it from `Design/road-signs/` |

**Safe area** (`terrain.safeArea`): top 220, bottom 320, sides 72. Text and markers stay inside it; the land bleeds everywhere.

## Variants (previews)

| Preview | Shows |
|---|---|
| `i80-terrain.png` | Salt Lake City to Sacramento (mockup route), Donner Summit, an illustrative 60-mile altitude gap. z7 elevation |
| `brenner-terrain.png` | Innsbruck to Bolzano, a pass name, km. z10 elevation |
| `brenner-terrain-long-labels.png` | German strings, a 2-line title, a long summit name, safe area (pink) and route band (blue) |
| `nullarbor-flat.png` | Flat land: the 1,200 m minimum span keeps exaggeration calm; the Great Australian Bight as water |
| `i80-altitude-unavailable.png` | No usable absolute altitude: flat land with land-cover colour, no summit, "Elevation unavailable" chip |
| `i80-hide-route.png` | Framed on the two named places' city centres, a pin and name each. No route, route light or summit |

Route geometry: I-80 from `docs/plan/mockups/source/`; Brenner (A13/A22) and Nullarbor (Eyre Highway) from OSRM (© OpenStreetMap contributors, ODbL), ends trimmed 8 km, "recorded" altitude sampled from z10 elevation and smoothed. Tiles, land cover and routes are cached in `Tools/design/.cache/` and never committed.

## Contrast

Text sits on the scrims and carries the text shadow (grow 3 px, blur 6, 75 % ink), the same recipe as the Print card, which passes a glyph-local 3:1 check on a bright sky photo. Token pairs against the background are unchanged from style 3 (text 15.7:1, secondary 7.8:1, amber 10.3:1). A glyph-local check over the relief, like `Tools/design/print-card.mjs` does on photos, is still to do before release.

## Rebuilding

```bash
cd Tools/design && npm install && npm run fonts
pip install --user numpy scipy pillow   # terrain_relief.py
python3 fetch_landcover.py              # once: Natural Earth land cover → .cache/ne/ne1_2min.png (75 MB download)
node terrain-previews.mjs               # all six previews and both templates (about 4 min; --reuse skips relief rebuilds)
node contact-sheet.mjs
```

The first run downloads about 70 MB of elevation tiles into `.cache/terrarium/`. The relief script needs about 1.5 GB of RAM.

## Handoff

- **Platform (`RoadPrintCore`, [ROA-10](/ROA/issues/ROA-10)):** framing, mesh, tile choice and decoding, light, occlusion, haze, visibility and the rasteriser (ADR 0006). It reads `terrain.camera`, `terrain.layout` (horizon, near edge, route band), `terrain.hillshade`, `terrain.occlusion`, `terrain.landCover`, `terrain.snow`, `terrain.water`, `terrain.land`, `terrain.haze`, `terrain.sky`, `terrain.edgeFade`, `terrain.routeLight` and `terrain.ribbon.depthBias`. Mesh size and the tile budget are engineering configuration, not tokens.
- **iOS ([ROA-12](/ROA/issues/ROA-12)):** draws the relief image, then scrims, ribbon, summit and type in Canvas from the generated token constants, and handles the offline state.
- **Data ([ROA-9](/ROA/issues/ROA-9)):** with ADR 0006, only the land-cover palette and the mask are bundled.
