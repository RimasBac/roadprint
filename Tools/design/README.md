# Design tools

Node scripts that render `Design/` SVGs to PNG on the Linux server. No browser is needed.

- **Dependency:** `@resvg/resvg-js`, a Rust SVG renderer with prebuilt binaries. It is only for design previews and doesn't ship in the app.
- **Fonts:** fetched as full static TTFs (SIL OFL) from the Google Fonts CSS API into `fonts/`. They are git-ignored.

```bash
cd Tools/design
npm install
npm run fonts                                   # Inter + Barlow Condensed
node render.mjs path/to/file.svg [--width 60] [--out dir]
python3 fetch_landcover.py                      # once: Natural Earth land cover at 2′ (75 MB)
node terrain-previews.mjs [variant ...]         # Terrain card previews (ROA-11); calls terrain_relief.py
node contact-sheet.mjs                          # 3×2 sheet of the Terrain previews
node road-signs.mjs                             # road-sign templates, signs.json, previews (ROA-49)
node print-card.mjs                             # Print card SVGs, previews, contact sheet, contrast checks (ROA-57)
```

## Notes

- **Font outlines.** `ttf.mjs` is a small TrueType reader (outlines and advance widths, no kerning). `road-signs.mjs` uses it to outline the "INTERSTATE" lettering and to measure and place the preview numbers, so the previews don't depend on resvg's font matching.

- **Text fallback.** resvg falls back to another font for a whole `<text>` element when one glyph is missing. Barlow Condensed has no `→`, so the preview builder draws the arrow as its own Inter element. The app's native text layout doesn't have this problem.
- **Condensed fonts.** Condensed fonts need `font-stretch="condensed"` for resvg to match them.
- **Relief layer.** `terrain_relief.py` (Python 3 with numpy, scipy and pillow: `pip install --user numpy scipy pillow`) fetches public AWS Terrain Tiles, averages them to the ADR 0001 2′ grid, colours them with Natural Earth land cover, and paints the flat-shaded mesh. It needs network access on the first run; tiles and OSRM routes are cached in `.cache/` (git-ignored). It is a style preview, not dataset validation. See `Design/cards/terrain/README.md`.

## MapScene (ROA-52)

The core lays out map art; `scene-preview.mjs` only draws its ordered layers.
The existing resvg dependency renders PNGs without an Apple runtime. No new dependencies.

```sh
# CI runs this on Linux (the development server has no Swift toolchain):
MAP_SCENE_OUTPUT_DIR="$PWD/build/map-scene" swift test --package-path RoadPrintCore --filter MapSceneTests
npm ci --prefix Tools/design
node Tools/design/fetch-fonts.mjs
node Tools/design/scene-preview.mjs build/map-scene/i80-390x460.json build/map-scene night
node Tools/design/scene-preview.mjs build/map-scene/europe-390x460.json build/map-scene day
node Tools/design/scene-comparison.mjs build/map-scene/i80-390x460-night@2x.png build/map-scene/i80-vs-mockup@2x.png
```

The `core-tests` workflow uploads `map-scene-previews` on success or failure:
I-80 in three sizes, synthetic Kaunas–Verona, a 3 km trip, JSON, SVG and 2×
night/day PNGs. The reference crop keeps the mockup's 390×300 pt map unchanged
inside a 390×460 pt comparison panel; it is padded, never stretched.

The initial golden in
`RoadPrintCore/Tests/RoadPrintCoreTests/Fixtures/map-scene-i80-golden.json`
was captured by Linux CI run 43168084113 at f976845. Tests compare every number
with 0.01 pt tolerance and check all keys and arrays. To update intentionally,
copy `i80-390x460.json` from the CI artifact and review the geometry diff.
Do not regenerate it automatically or accept it in place of visual review.

Timing is a release-build mean of five I-80 builds after loading `PlaceIndex`;
the assertion is <150 ms. Debug tests check geometry and a <200 KB scene JSON.
The I-80 JSON has no elevations; its summit is an explicit synthetic Donner
Pass input (39.33, −120.34, 2,206 m), not a claimed altitude lookup.

Visual review is required and remains **PENDING**, Designer by default,
with the integrated Canvas map in ROA-54 per FEEL_STANDARD §8. These renders
are implementation evidence. They do not establish a visual PASS or verify
VoiceOver order, haptics, animation or device scrolling.
