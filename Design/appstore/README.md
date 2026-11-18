# App Store screenshots (ROA-96)

Five framed screenshots for the 1.0 listing (plan §12.2). Each one has a night background, a two-line caption in Barlow Condensed Bold and the raw screenshot below it, with rounded corners, a soft shadow and a thin border. There is no device bezel.

| # | Caption (line 1 in text colour, line 2 in amber) | Screen |
|---|---|---|
| 01 | EVERY TRIP, / DRAWN AS ART | Trip complete |
| 02 | SHARE YOUR ROAD / AS A CARD | Share card sheet |
| 03 | YOUR PRINT OF / EVERY ROAD | My map |
| 04 | ONE TAP TO START. / ONE TO END. | Drive |
| 05 | JOIN THE / MILLION-MILE CLUB | You (career miles) |

- `frame.svg` is the 1320 × 2868 template. `caption-line-1` and `caption-line-2` are text placeholders, and `screenshot-placeholder` is the screen area (x 160, y 600, 1000 × 2173, corner radius 92).
- `out/01.png` to `out/05.png` are the files to upload. They are exactly 1320 × 2868, 8-bit RGB, with no alpha channel.
- `previews/` is the same frame with crops of `docs/plan/mockups/` standing in until the real screenshots arrive. Don't upload these.
- Contrast: #f0efec on the background is at least 15.7:1, and amber #ffb547 is at least 10.3:1.

## Regenerate

```bash
cd Tools/design && npm ci && node fetch-fonts.mjs
node appstore.mjs --in /path/to/raw-screenshots   # 5 raw 1320×2868 PNGs, name order = screenshot order
node appstore.mjs                                 # no input: stand-ins into previews/
```

The captions live in `CAPTIONS` in `Tools/design/appstore.mjs`. They are outlined from the font, so a long line shrinks to fit.
