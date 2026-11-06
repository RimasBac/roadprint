# RoadPrint mockup source

The scripts that generated the PNG mockups.

## Files

- `fetch.mjs` downloads real routes from the public OSRM routing server and saves them to `routes.json`.
- `elev.mjs` samples elevation along I-80 (Open-Meteo) and saves it to `elev.json`.
- `gen.mjs` builds the HTML pages: `p1.html` (trip summary), `p2.html` (share cards) and `p3.html` (heatmaps).
- `shoot.cjs` screenshots those pages to PNG with Playwright.

## Rebuild the mockups

`routes.json` and `elev.json` are included, so you can skip `fetch.mjs` and `elev.mjs`.

1. Install the dependencies:

   ```bash
   npm install
   ```

2. Build the HTML pages:

   ```bash
   node gen.mjs
   ```

3. Take the screenshots. `shoot.cjs` saves to `/home/user/mockups/`, so change that path inside the file first.

   ```bash
   node shoot.cjs
   ```

## Licenses

- Map data: us-atlas / US Census (public domain).
- Fonts: Inter and Barlow Condensed (SIL Open Font License).
