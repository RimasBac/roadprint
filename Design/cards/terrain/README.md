# Terrain share card (Pro)

Style `terrain-style-3` for the Terrain card in plan §4.4 and ADR [0001](../../../docs/adr/0001-terrain-card.md). Export size is 1080×1920 px, sRGB. **The board approved this style on 2026-11-09** ([ROA-11](/ROA/issues/ROA-11)). That approval includes extending the plan §5.1 palette with the land-cover, snow and water colours below.

All values live in [`Design/tokens.json`](../../tokens.json) under `terrain.*`. The SVGs and previews here are built from those tokens. If a file disagrees with the tokens, the tokens win. Every size is in export pixels.

## Files

| File | What it is |
|---|---|
| `terrain-card.svg` | Editable composition template. Shows the layer order, the slots and the placeholder text. The `#ribbon-*` paths are style samples only |
| `terrain-card-hide-route.svg` | Template for the "Hide route on card" option: places and stats only, over relief framed on the two named places' city centres |
| `previews/*.png` | 1080×1920 previews (see below) and `contact-sheet.png` |

## Layer order (bottom to top)

1. `#background` `#14161c`
2. `#relief-slot`, full width, centred on y 380–1280 (far peaks may rise above it). The app paints the core's triangle list far-to-near, one flat colour per triangle. No screen-space fades: the core bakes them into the colours (see "Relief look").
3. Ribbon, in this order:
   1. `ribbon-occluded`: amber at 55 % opacity, 4 px, dash 12/10
   2. `ribbon-gap`: grey `#a6aab4` dots, 5 px, round caps every 13 px
   3. glow 0: 14 px, blur 6, 65 % opacity
   4. glow 1: 24 px, blur 22, 35 % opacity
   5. casing: `#14161c`, 14 px, 85 % opacity (separates amber from tan desert)
   6. core: amber, 8 px
4. `#route-ends`: approximate start and end circles (r 16, 3 px stroke, 18 % fill), because trip ends are trimmed.
5. `#summit`: marker (r 9 `#f0efec` with a 4 px background ring), a vertical leader (2 px, 70 % opacity, 120 px long) and a label plate (`#14161c` at 85 %, radius 14, padding 14).
6. Header, stats and road sign.

## Relief look (terrain-style-3)

What makes the relief read as 3D instead of a grey slab. Each step is plain per-vertex or per-triangle maths, so it belongs in `RoadPrintCore` and ports to Android as is:

1. **Ground colour** (`terrain.landCover`): Natural Earth I land cover (public domain, already a project data source) at the same 2′ grid as the elevation: green forest, tan desert, rock. It is graded for the dark card: saturation 1.6, gamma 1.35, brightness 0.64. **This extends the plan §5.1 palette, at the board's request** (ROA-11: "the 3D should have colour, not all grey"). Water is `terrain.water` (`#15212e`, edge `#2b3d52`).
   - **Snow** (`terrain.snow`): above 2,600 m the ground blends toward `#f0efec`, fully by 3,300 m (85 %).
   - **App cost, for the CTO:** the land cover adds a global 10800×5400 RGB layer next to the elevation grid. Compressed size is not measured yet; the 2′ PNG is 30 MB, and a palette-indexed or HEIF version should be far smaller.
2. **Hillshade** (`terrain.hillshade`): Lambert shading with smooth vertex normals on the exaggerated mesh, light from 300°, 32° up. Each triangle takes the mean of its three vertex shades. Shading each face alone makes neighbours flip between light and dark along the diagonal, which shows as a checkerboard.
3. **Occlusion** (`terrain.occlusion`): `h − boxBlur(h, 6 cells)` darkens valleys and lifts ridges.
4. **Route light** (`terrain.routeLight`): heat-ramp `#c2650f` added around the route, a 26 px gaussian at 0.35. It ties the ribbon to the ground. It is not drawn in hide-route mode.
5. **Haze** (`terrain.haze`): far rows blend to the background colour (0.78 · depth^1.5).
6. **Edge fade** (`terrain.edgeFade`): sides 16 %, near 14 %, far 20 % of the footprint blend to the background, so the terrain dissolves instead of ending in a cut slab.
7. **Exaggeration** (`terrain.camera.exaggeration`): 0.065 × footprint width ÷ relief, clamped to 1.5–10×. Above about 10× the 2′ cells turn into needles (I-80 at 25× looked like a hedgehog).
8. **Camera**: north-up, 34° elevation, orthographic.

**Mesh size:** the previews use a **240×240** mesh. ADR 0001 says "initially 160×160", but at 1080 px wide 160 gives about 7 px quads, which show as a staircase. 240 gives about 4.5 px quads (about 115k triangles). This is a proposal for the CTO and Platform Engineer, not a token.

### Ribbon rules (ADR 0001)

- **Visible:** glow plus core, drawn at the *recorded* altitude, with the same vertical exaggeration as the land.
- **Occluded:** the coarse relief hides this part. It is drawn as an x-ray dash at the same projected position, with no glow. A point counts as occluded when the terrain between it and the camera rises more than `depthBias` (10 px on screen) above the sight line. 10 px absorbs the way 2′ averaging fills narrow valleys; at 3 px over half of the Brenner route was dashed.
- **Gap:** a recording gap or invalid altitude. It is drawn as a straight dotted link between the last and next valid points, never interpolated and never glowing. It looks deliberately different from occluded, so a tunnel or gap is never mistaken for terrain.

### Summit label placement

The label tries these placements in order:

1. Above the marker, on the open side (the side towards the card centre).
2. Above, on the other side.
3. Below, on the open side.
4. Below, on the other side.
5. The same four again with the leader ×1.5, then ×2.

The first placement where the plate stays inside the relief frame and the side safe area, and doesn't cover the ribbon, wins.

The kicker is "Highest recorded point". Show the name line only when trusted offline enrichment provides a name (for example a legendary-road zone). The marker sits on the highest valid recorded sample after the privacy trim.

## Text slots

All text is a live placeholder that the app fills from `TripShareSummary` and the String Catalog.

| id | Style token | Notes |
|---|---|---|
| `kicker-date` | `type.kicker` | Upper case, localized long date |
| `title-line-1/2` | `type.title` | "From → To", at most 2 lines, wrap at the arrow |
| `summit-kicker/value/name` | `type.summit*` | Value in the user's unit. The name is optional |
| `stat-number`, `stat-unit` | `type.number`, `type.unit` | Unit x = number advance + 18 |
| `stat-chip-n` | `type.chip` | Height 72, radius 36, padding 28, gap 16 |
| `road-sign-slot` | n/a | 72 px. Fill it from `Design/road-signs/` |
| `notice-elevation-unavailable` | `type.notice` | Flat layout only. It replaces `#summit` |

**Safe area** (`terrain.safeArea`): top 220, bottom 320, sides 72. Keep text and markers inside it. The relief may bleed outside it.

## Variants (previews)

| Preview | Shows |
|---|---|
| `i80-terrain.png` | The real I-80 route from Salt Lake City to Sacramento (mockup data), the Donner Summit label, and an illustrative 60-mile altitude gap |
| `brenner-terrain.png` | Innsbruck to Bolzano, a pass name, km |
| `brenner-terrain-long-labels.png` | German strings, a 2-line title, a long summit name, and safe-area guides |
| `nullarbor-flat.png` | Flat landscape: the 1,200 m minimum span keeps exaggeration calm; the Great Australian Bight shows as water |
| `i80-altitude-unavailable.png` | No usable absolute altitude: a flat, unshaded land-cover plane, no heights, no summit, and an "Elevation unavailable" notice |
| `i80-hide-route.png` | The board asked for a real picture here. Relief framed on the two named places' **city centre points** (the same places the title shows, from offline place lookup, never trip points), with a pin and name for each. No route, no route light, no route-shaped crop, no summit location |

### Real elevation and colour, but not the bundle

The relief uses **real elevation**: AWS Terrain Tiles (Terrarium, z7) box-averaged to 2′ cells on the global 2′ lattice, which is what the ETOPO 2022 bundle in ADR 0001 stores. It is then bicubic-resampled onto the mesh, so it shows no more detail than the app can. Colour comes from Natural Earth I land cover (`NE1_LR_LC`) box-resampled to the same 2′ grid.

It is still a **style preview, not dataset validation**. The real bundle from [ROA-9](/ROA/issues/ROA-9) has to be checked against this style before release.

- I-80 uses the real mockup route and elevation profile from `docs/plan/mockups/source/`. The 60-mile altitude gap is illustrative.
- Brenner (A13/A22, 118.9 km) and Nullarbor (Eyre Highway) use OSRM road geometry (© OpenStreetMap contributors, ODbL). The "recorded" altitude is z10 elevation sampled on the road and smoothed. Trip ends are trimmed 8 km.
- Terrain tiles, the land-cover raster and routes are cached in `Tools/design/.cache/` and never committed.

Every preview carries a stamp saying this, and the stamp is never part of the card.

## Contrast (WCAG, measured against the token colours)

| Pair | Ratio |
|---|---|
| Text `#f0efec` on the background | 15.7:1 |
| Secondary text on the background | 7.8:1 |
| Amber on the background | 10.3:1 |
| Text on a chip | 14.1:1 |
| Secondary text on a chip | 7.0:1 |
| Secondary text on the summit plate over the brightest lit relief | about 5.5:1 |

On the brightest relief, amber's luminance is close to the land colour. That is why the ribbon has the dark casing and the glow.

## Rebuilding

```bash
cd Tools/design && npm install && npm run fonts
pip install --user numpy scipy pillow   # terrain_relief.py
python3 fetch_landcover.py       # once: Natural Earth land cover → .cache/ne/ne1_2min.png (75 MB download)
node terrain-previews.mjs        # all six previews (about 2 min; add --reuse to skip relief rebuilds)
node contact-sheet.mjs
node render.mjs ../../Design/cards/terrain/*.svg --out ../../Design/cards/terrain/previews
```

## Handoff

The iOS Engineer draws the core draw list and the overlays in Canvas from the generated token constants ([ROA-12](/ROA/issues/ROA-12)). The Platform Engineer's core uses the `terrain.camera`, `terrain.hillshade`, `terrain.occlusion`, `terrain.landCover`, `terrain.snow`, `terrain.water`, `terrain.land`, `terrain.haze`, `terrain.edgeFade`, `terrain.routeLight` and `terrain.ribbon.depthBias` tokens ([ROA-10](/ROA/issues/ROA-10)). `Tools/design/terrain_relief.py` is a readable reference for the colour maths. Mesh size, footprint minimum and quality limits are engineering configuration, not tokens.
