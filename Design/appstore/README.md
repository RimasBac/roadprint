# App Store screenshots (ROA-96)

Five framed screenshots for the 1.0 listing (plan §12.2). The captions speak to truck drivers in their own terms (haul, lanes, run) and name the privacy promise. Each one has a night background, a two-line caption in Barlow Condensed Bold and the raw screenshot below it, with rounded corners, a soft shadow and a thin border. There is no device bezel.

| # | Caption (line 1 in text colour, line 2 in amber) | Screen |
|---|---|---|
| 01 | EVERY MILE YOU HAUL, / LOGGED AND MAPPED | Trip summary (`01-trip-summary`) |
| 02 | SHOW OFF / YOUR LANES | Share sheet, Night Highway (`02-night-highway`) |
| 03 | EVERY ROAD YOU'VE RUN, / LIT UP ON ONE MAP | My map, lifetime, several distinct roads (`03-my-map`) |
| 04 | ONE TAP TO START. / NO ACCOUNT. NO ADS. | Drive, idle (`04-drive`) |
| 05 | POST YOUR RUN / AS A VIDEO | Share sheet, Video tab mid-draw (`05-trip-card-video`) |

The inputs are matched by sorted file name, so ROA-95's fifth capture lands in 05 whatever its exact name. No light-theme or Road Atlas promotion: the board wants the night look and the trip video instead. The caption doesn't say Pro, because 1.0 sells no Pro tier yet; add WITH PRO only when the build gates Video behind Pro.

- `frame.svg` is the 1320 × 2868 template. `caption-line-1` and `caption-line-2` are text placeholders, and `screenshot-placeholder` is the screen area (x 160, y 600, 1000 × 2173, corner radius 92).
- `out/01.png` to `out/05.png` are the files to upload. They are exactly 1320 × 2868, 8-bit RGB, with no alpha channel.
- `previews/` is the same frame with crops of `docs/plan/mockups/` standing in (05 adds a play button over the Night Highway card) until the real screenshots arrive. Don't upload these.
- Contrast: #f0efec on the background is at least 15.7:1, and amber #ffb547 is at least 10.3:1.

## Regenerate

```bash
cd Tools/design && npm ci && node fetch-fonts.mjs
node appstore.mjs --in /path/to/raw-screenshots   # the 5 PNGs from the ROA-95 `appstore-screenshots` artifact (01-trip-summary … 05-trip-card-video)
# --in requires exactly those five file names; a stale set (e.g. 05-road-atlas.png) is rejected and the missing file is named.
node appstore.mjs                                 # no input: stand-ins into previews/
```

The captions live in `CAPTIONS` in `Tools/design/appstore.mjs`. They are outlined from the font, so a long line shrinks to fit.
