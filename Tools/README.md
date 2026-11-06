# Tools

Data-prep scripts. Run on the server (Node or Python).

## fixtures/make-gpx.mjs

Builds GPX test fixtures for `RoadPrintCore` (and the iOS UI test replay) plus `expected.json`, which holds distance, moving time, gap and stop counts computed independently of the Swift code.

```
node Tools/fixtures/make-gpx.mjs
```

Output: `RoadPrintCore/Tests/RoadPrintCoreTests/Fixtures/` (`i80-ui-test.gpx`, `i80-long-stop.gpx`, `i80-gap.gpx`, `expected.json`). Output is deterministic; keep the thresholds at the top of the script in sync with `RecordingHeuristics.default`.

**Source and licence:** the geometry is the I-80 Salt Lake City → Sacramento route (`SLC-SAC`) in `docs/plan/mockups/source/routes.json`, routed with OSRM on OpenStreetMap data, © OpenStreetMap contributors, ODbL 1.0. Timestamps and altitudes are synthetic (about 100 km/h, 5 m altitude jitter).

## places/build.mjs

Builds `RoadPrintCore/Sources/RoadPrintCore/Resources/places.rpgeo`: country and admin-1 region outlines for offline "countries and regions crossed" labels (`PlaceIndex`). Format: `Tools/places/FORMAT.md`.

```
cd Tools/places
npm install --include=dev      # mapshaper only (dev dependency, see below)
node build.mjs
node make-fixture.mjs          # only to regenerate the sparse I-80 route test fixture
```

- **Input:** Natural Earth 5.1.1, 1:10m `ne_10m_admin_0_countries.zip` and `ne_10m_admin_1_states_provinces.zip`, downloaded from `https://naciscdn.org/naturalearth/10m/cultural/` into `Tools/places/out/` (git-ignored). The script checks the SHA-256 of each zip (pinned in `build.mjs`) and fails if Natural Earth changed it:
  - `ne_10m_admin_0_countries.zip` `ce1ac7036499a0edd641fbc093cd209a98f96a49d2eca8480aaacad35138a7f6`
  - `ne_10m_admin_1_states_provinces.zip` `efc59726337323058f9446210adc96673179cd344e053666ee3d28cb58ba2b05`
- **Simplification:** `mapshaper` (npm, dev dependency of `Tools/places` only; it simplifies shared borders topologically, so neighbours don't get gaps or overlaps). Visvalingam, 700 m interval. 500 m gave 4.5 MB, over the 4 MB limit.
- **Codes:** country `ISO_A2_EH` (plain `ISO_A2` is `-99` for France and Norway), region `iso_3166_2`. NE's France regions are departments (Paris is `FR-75`, not `FR-IDF`).
- **Output** is deterministic (same input, byte-identical file). Current file: 3,809,956 bytes, sha256 `3f276af05a7fd170609740bb7cfa7dc786b743550a219049b34adf97cdb48a84`, 258 countries, 4,407 regions.
- **Licence and attribution:** Natural Earth is in the public domain. "Made with Natural Earth." Settings shows this credit (M7). `Tools/places/make-fixture.mjs` uses the OSRM/OpenStreetMap route in `docs/plan/mockups/source/routes.json`, © OpenStreetMap contributors, ODbL 1.0.
