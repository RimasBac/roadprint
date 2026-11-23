# Promo video

An Apple-style vertical promo (1080×1920, 30 fps, about 28 s) for the website and social media.
It is **not** the App Store preview: Apple allows only screen captures there (`Tools/appstore-preview/`).

**Every app pixel is a real screenshot of the app**: the App Store captures from the
`appstore-screenshots` CI artifact. The phone screen shows one, pop-outs lift whole UI elements
out of it (leaving an empty slot behind), and the backdrop is a blurred copy. The only additions
are a generic phone body (no Apple artwork), light, headlines in the app's Barlow Condensed and
camera moves. `promo.json` can only name captures and rectangles of them; any other key is refused.

| Scene | Screenshot | Headline | Pop-out |
|---|---|---|---|
| map | 03-my-map | EVERY ROAD YOU'VE RUN, / LIT UP ON ONE MAP | none yet |
| drive | 04-drive | ONE TAP TO START. / NO ACCOUNT. NO ADS. | Start Trip |
| summary | 01-trip-summary | EVERY MILE YOU HAUL, / LOGGED AND MAPPED | trip map, elevation card |
| card | 02-night-highway | SHOW OFF / YOUR LANES | share card, turned to the camera |
| end | 02-night-highway | ROADPRINT / EVERY ROAD. ONE MAP. | (end card) |

05-trip-card-video is not used: as a still it is a half-drawn route.

## Make it

CI makes it with the store screenshots: `ios-build` with `evidence=appstore` uploads the
`promo` artifact. To make it from downloaded captures (needs Node 22):

    cd Tools/promo-video && npm ci
    node render.mjs --shots path/to/appstore-screenshots --out out \
      [--drop SCENE] [--stills-only] [--music licensed-track.m4a] [--badge app-store-badge.svg]

Review stills of every scene and pop-out go to `out/stills/` first; `--stills-only` stops there.
`--drop map` leaves a scene out. `PROMO_CONCURRENCY` sets parallel frames (default 1).

If the CI artifact has expired, `node framed-shots.mjs --out shots` crops the real captures out of
`Design/appstore/out` (at 75.8 % size), never out of `previews/`, which holds design mock-ups.

## Change it

- Timing, headlines, camera poses (`rx`, `ry` in degrees, `z`, `y` in px) and pop-outs: `promo.json`.
  `pose.from` is where the camera starts when that scene opens the promo; later scenes continue
  from the scene before.
- A pop-out is a rect in fractions `[x, y, width, height]` of one screenshot. Measure it on that
  capture and take the whole element (the full card or map), so nothing is cut through.
  After a new capture moves the layout, re-measure.
- `--badge` must be Apple's official "Download on the App Store" SVG, used under Apple's marketing
  guidelines. Music must be licensed for this use.
- Live preview: `npx remotion studio src/index.ts --props=out/props.json` after a render.
- Tests: `npm test`.

## Licence

Remotion is free for individuals and companies of up to three people; larger companies need a
Remotion company licence (https://remotion.pro).
