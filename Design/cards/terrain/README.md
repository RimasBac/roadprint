# Terrain share card (Pro)

Style `terrain-style-1` for the Terrain card in plan §4.4 and ADR [0001](../../../docs/adr/0001-terrain-card.md). Export size is 1080×1920 px, sRGB. **The board has not approved this style yet**, so it must not go into the app before that approval ([ROA-11](/ROA/issues/ROA-11)).

All values live in [`Design/tokens.json`](../../tokens.json) under `terrain.*`. The SVGs and previews here are built from those tokens. If a file disagrees with the tokens, the tokens win. Every size is in export pixels.

## Files

| File | What it is |
|---|---|
| `terrain-card.svg` | Editable composition template. Shows the layer order, the slots and the placeholder text. The `#ribbon-*` paths are style samples only |
| `terrain-card-hide-route.svg` | Template for the "Hide route on card" option: places and stats only, on the generic backdrop |
| `terrain-backdrop.svg` | Generic backdrop for hide-route, 1080×900. It is the same for every trip and encodes no route, place or summit |
| `previews/*.png` | 1080×1920 previews (see below) and `contact-sheet.png` |

## Layer order (bottom to top)

1. `#background` `#14161c`
2. `#relief-slot` at y 380–1280, full width. The app draws the core's draw list here: shaded triangles, then water.
3. `#relief-fade-top` (200 px) and `#relief-fade-bottom` (220 px). Gradients to the background colour.
4. Ribbon, in this order:
   1. `ribbon-occluded`: amber at 55 % opacity, 4 px, dash 12/10
   2. `ribbon-gap`: grey `#a6aab4` dots, 5 px, round caps every 13 px
   3. glow 0: 14 px, blur 6, 65 % opacity
   4. glow 1: 24 px, blur 22, 35 % opacity
   5. casing: `#14161c`, 13 px, 60 % opacity
   6. core: amber, 8 px
5. `#route-ends`: approximate start and end circles (r 16, 3 px stroke, 18 % fill), because trip ends are trimmed.
6. `#summit`: marker (r 9 `#f0efec` with a 4 px background ring), a vertical leader (2 px, 70 % opacity, 120 px long) and a label plate (`#14161c` at 85 %, radius 14, padding 14).
7. Header, stats and road sign.

### Ribbon rules (ADR 0001)

- **Visible:** glow plus core, drawn at the *recorded* altitude, with the same vertical exaggeration as the land.
- **Occluded:** the coarse relief hides this part. It is drawn as an x-ray dash at the same projected position, with no glow. A point counts as occluded when it is more than `depthBias` (3 px) behind the terrain horizon.
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
| `nullarbor-flat.png` | Flat landscape: the 1,500 m minimum ramp span keeps flat land dark and quiet, and the ocean at sea level uses the background colour |
| `i80-altitude-unavailable.png` | No usable absolute altitude: a flat land plane, no heights from the elevation data, no summit, and an "Elevation unavailable" notice |
| `i80-hide-route.png` | Places and stats only on the generic backdrop. No route, no route-shaped crop, no summit location |

### These previews are composition placeholders, not a data check

The relief in every preview is **synthetic**. It is a procedural heightfield shaped like each region, then box-filtered to the 2′ ETOPO grid spacing in ADR 0001 so it shows no more detail than the bundled data can.

So these previews show the composition only. They don't show what real ETOPO 2022 relief looks like. Once [ROA-9](/ROA/issues/ROA-9) produces the bundle, its real-data crops are the dataset check, and this style should be checked against them before release.

- I-80 uses the real mockup route and elevation profile from `docs/plan/mockups/source/`.
- Brenner and Nullarbor use hand-placed town waypoints.

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
node terrain-previews.mjs        # all six previews (about 1 min)
node contact-sheet.mjs
node render.mjs ../../Design/cards/terrain/*.svg --out ../../Design/cards/terrain/previews
```

## Handoff

The iOS Engineer draws the core draw list and the overlays in Canvas from the generated token constants ([ROA-12](/ROA/issues/ROA-12)). The Platform Engineer's core uses the `terrain.camera`, `terrain.hillshade`, `terrain.land` and `terrain.ribbon.depthBias` tokens ([ROA-10](/ROA/issues/ROA-10)). Mesh size, footprint minimum and quality limits are engineering configuration, not tokens.
