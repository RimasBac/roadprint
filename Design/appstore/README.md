# App Store screenshots (ROA-96)

Five framed screenshots for the 1.0 listing (plan §12.2). Each one has a night background, a two-line caption in Barlow Condensed Bold and the raw screenshot below it, with rounded corners, a soft shadow and a thin border. There is no device bezel.

| # | Caption (line 1 in text colour, line 2 in amber) | Screen |
|---|---|---|
| 01 | YOUR DRIVE, / DRAWN IN LIGHT | Trip summary (`01-trip-summary`) |
| 02 | SEND A POSTCARD / FROM THE ROAD | Share sheet, Night Highway (`02-night-highway`) |
| 03 | ALL YOUR ROADS, / ONE MAP | My map, lifetime, several distinct roads (`03-my-map`) |
| 04 | ONE TAP / BEFORE YOU GO | Drive, idle (`04-drive`) |
| 05 | SHARE A TRIP VIDEO / WITH PRO | Share sheet, Video state in a Pro session (`05-…`, the fifth file by name) |

The inputs are matched by sorted file name, so ROA-95's fifth capture lands in 05 whatever its exact name. No light-theme or Road Atlas promotion: the board wants the night look and the Pro video instead.

- `frame.svg` is the 1320 × 2868 template. `caption-line-1` and `caption-line-2` are text placeholders, and `screenshot-placeholder` is the screen area (x 160, y 600, 1000 × 2173, corner radius 92).
- `out/01.png` to `out/05.png` are the files to upload. They are exactly 1320 × 2868, 8-bit RGB, with no alpha channel.
- `previews/` is the same frame with crops of `docs/plan/mockups/` standing in (05 adds a play button and PRO pill over the Night Highway card) until the real screenshots arrive. Don't upload these.
- Contrast: #f0efec on the background is at least 15.7:1, and amber #ffb547 is at least 10.3:1.

## Regenerate

```bash
cd Tools/design && npm ci && node fetch-fonts.mjs
node appstore.mjs --in /path/to/raw-screenshots   # the 5 PNGs from the ROA-95 `appstore-screenshots` artifact (01-trip-summary … 05, the Pro video)
node appstore.mjs                                 # no input: stand-ins into previews/
```

The captions live in `CAPTIONS` in `Tools/design/appstore.mjs`. They are outlined from the font, so a long line shrinks to fit.
