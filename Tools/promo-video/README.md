# Promo video

An Apple-style vertical promo (1080×1920, 30 fps) for the website and social media. It is
**not** the App Store preview: App Store previews may only show screen captures
(`Tools/appstore-preview/`).

Every app pixel comes from the same simulator recording the App Store preview uses. The phone
screen plays the recording, pop-outs are crops of it lifted toward the camera, and the backdrop
is a blurred copy of it. The only additions are a generic phone body, light, headlines (Barlow
Condensed, from the app) and camera moves. `promo.json` accepts only timings, poses, headlines
and the names of regions the UI test measured. Any other key, such as an image, is rejected.

## Make it

CI makes it with the App Store preview: `ios-build` with `evidence=apppreview` uploads it in the
`app-preview` artifact under `promo/`. To re-cut from a downloaded recording (needs Node 22):

    cd Tools/promo-video && npm ci
    node render.mjs --raw raw.mov --clock record-start.txt --markers RoadPrint --out out \
      [--stills-only] [--music licensed-track.m4a] [--badge app-store-badge.svg]

Stills of every scene and pop-out are written to `out/stills/` first; `--stills-only` stops
there. `PROMO_CONCURRENCY` sets parallel frames (default 1, for the 4 GB server).

## Change it

- Timing, headlines, phone poses (`rx`, `ry` in degrees, `z`, `y` in px) and pop-outs:
  `promo.json`. A pop-out names a region from the UI test's `rects`; `face` turns it toward the
  camera and brings it to the centre.
- New regions: add `rect("name", element)` in `AppStorePreviewTests` and re-record.
- `--badge` must be Apple's official "Download on the App Store" SVG, used under Apple's
  marketing guidelines. Without it the end card shows no badge.

## Licence

Remotion is free for individuals and companies of up to three people; larger companies need a
Remotion company licence (https://remotion.pro).
