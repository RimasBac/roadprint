# Design tools

Node scripts that render `Design/` SVGs to PNG on the Linux server. No browser is needed.

- **Dependency:** `@resvg/resvg-js`, a Rust SVG renderer with prebuilt binaries. It is only for design previews and doesn't ship in the app.
- **Fonts:** fetched as full static TTFs (SIL OFL) from the Google Fonts CSS API into `fonts/`. They are git-ignored.

```bash
cd Tools/design
npm install
npm run fonts                                   # Inter + Barlow Condensed
node render.mjs path/to/file.svg [--width 60] [--out dir]
node terrain-previews.mjs [variant ...]         # Terrain card previews (ROA-11)
node contact-sheet.mjs                          # 3×2 sheet of the Terrain previews
```

## Notes

- **Text fallback.** resvg falls back to another font for a whole `<text>` element when one glyph is missing. Barlow Condensed has no `→`, so the preview builder draws the arrow as its own Inter element. The app's native text layout doesn't have this problem.
- **Condensed fonts.** Condensed fonts need `font-stretch="condensed"` for resvg to match them.
- **Synthetic relief.** `terrain-previews.mjs` uses synthetic relief, band-limited to the 2′ grid. It checks composition, not data. See `Design/cards/terrain/README.md`.
