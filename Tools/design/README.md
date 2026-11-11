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
