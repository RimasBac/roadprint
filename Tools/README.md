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

## roads/build.mjs

Builds `RoadPrintCore/Sources/RoadPrintCore/Resources/roads.rpgeo`: major roads for the "main road" guess (`RoadIndex`, `MainRoadGuesser`) behind the trip summary's road sign. Format: `Tools/roads/FORMAT.md`.

```
cd Tools/roads
npm install --include=dev      # mapshaper only
node --test normalise.test.mjs # ref and network mapping, 23 sample records
node build.mjs
node check.mjs <route.gpx|route.json>   # brute-force JS version of the guess, to cross-check the Swift
```

- **Input:** Natural Earth `ne_10m_roads.zip` 5.0.0 (sha256 `880b235383a1e1ccf33f4ea6f82b6755a2ffbce07e3974e412b43e88fe954ae9`) and, for country codes, `ne_10m_admin_0_countries.zip` 5.1.1 (same hash as above under places). Pinned in `build.mjs`. Kept: `Major Highway`, `Secondary Highway`, `Beltway`, `Bypass`. Ferries, tracks, plain roads and unknowns are dropped.
- **NE fields differ from the issue's guess:** there is no `sov_a3` outside North America, so the country comes from the admin-0 outlines. The route number is `name` (`"80"`), `label`/`label2` hold `E40`, `local` holds the national ref (`A10`, `M6`), `prefix` is `I`/`US`/`E`, `level` is `Interstate`/`Federal`/`State`/`E`.
- **Output** is deterministic. Current file: 817,675 bytes (0.78 MiB, limit 3 MB), sha256 `119c261ff2137d9a4183ec5a277ee59a5f9358d9f30c2f2a50f898e7be741bcf`, 11,724 roads, 169,945 vertices.
- **Licence and attribution:** Natural Earth is in the public domain. "Made with Natural Earth." Settings shows this credit (M7).

### Coverage of the plan's sign regions (Natural Earth 5.0.0)

| Region | Network | NE coverage |
|---|---|---|
| United States | `usInterstate`, `usHighway` | Good: interstates (1,539 records) and US highways (4,200). State routes fall back to `generic` |
| Canada | `canadaHighway` | Federal and provincial highways have numbers (647 records); no Trans-Canada marker, no names |
| Europe | `eRoad` | Good for E-roads (1,506 records). National refs (A7, N89) are only in `local`, so non-E roads become `generic`. The E-road wins over the national ref, as the plan's EU sign |
| United Kingdom | `ukMotorway`, `ukARoad` | Fair: M and A numbers from `local` (67 and 157 records); B roads absent |
| Australia | `australia` | **None.** All 405 NE records have empty name, label and local fields, so there is no ref and the road is not in the bundle. A trip across the Nullarbor has no main road in v1 |
| Elsewhere | `generic` | Mexico, Central America and New Zealand carry numbers; most of Asia, Africa and South America has no refs and is dropped |

## terrain/ (offline Terrain card data)

Builds the bundled terrain data described in `docs/adr/0001-terrain-card.md` and Amendment 1: a 2-arc-minute global height grid with a land/water bit, plus a 4-arc-minute land-cover palette raster. Format: `Tools/terrain/FORMAT.md`. Linux only; never runs on macOS CI and nothing here ships in the app except its output. `.github/workflows/tools-tests.yml` runs the fixture tests (including the byte-budget totals) on Linux for changes under `Tools/terrain/`.

```
python3 -m venv --without-pip venv && curl -sS https://bootstrap.pypa.io/get-pip.py | venv/bin/python   # only if the host has no pip/venv
venv/bin/pip install -r Tools/terrain/requirements.txt
# download the inputs into a NEW empty directory (URLs and sha256 are pinned in Tools/terrain/sources/sources.json)
venv/bin/python Tools/terrain/prepare_terrain.py   --etopo ETOPO_2022_v1_30s_N90W180_surface.tif --land ne_10m_land --lakes ne_10m_lakes --out OUT
venv/bin/python Tools/terrain/prepare_landcover.py --tif NE1_LR_LC.tif --out OUT
venv/bin/python Tools/terrain/verify_terrain.py OUT --compressed      # checksums, byte budget, size report
venv/bin/python Tools/terrain/previews.py OUT PREVIEWS NE1_LR_LC.tif  # review PNGs, not shipped
venv/bin/python Tools/terrain/make_release_zip.py OUT roadprint-terrain-v1.zip   # deterministic zip: size and sha256 go into bundle.lock.json
Tools/terrain/fetch_bundle.sh                                          # what everyone else runs: pinned download into App/Resources/Terrain/
venv/bin/python -m unittest discover -s Tools/terrain/tests          # fixture tests
```

- **Sources (pinned, checksummed, verified before any output is written):** NOAA NCEI ETOPO 2022 v1, 30 arc-second **surface (ice-surface)** GeoTIFF, 1,585,813,987 bytes, sha256 `8630abc4…a9e2` (DOI 10.25921/fd45-gt74, CC0); Natural Earth 1:10m `land` 5.1.1 and `lakes` 5.0.0 (the two releases differ; both pinned); Natural Earth I land cover `NE1_LR_LC` 2.0.0. Full URLs and hashes: `Tools/terrain/sources/sources.json`.
- **Why the 30″ product, not 15″:** it is NOAA's own aggregate of the same release, one 1.5 GB file instead of 288 tiles (about 7 GB), and divides exactly into 4×4 blocks per 2′ cell. The server has about 4 GB of free disk.
- **Resampling:** each 2′ cell is the area-weighted (cos latitude) mean of its 4×4 source samples, classified by Natural Earth polygon containment at sample centres (never by elevation sign). Land and water are aggregated separately; a mixed cell is land if land area ≥ water area. Ocean is 0 m; negative land is kept; no-data samples are excluded and an all-missing cell becomes `-32768`. Rounding is floor(x+0.5). Output is deterministic (no timestamps): repeated full runs from the pinned inputs give byte-identical tiles and land cover.
- **Lakes are flat water surfaces:** ETOPO holds lake-floor bathymetry, so each mapped Natural Earth lake gets one flat level, the median of the land samples within one source sample of its polygon (1,340 of 1,355 lakes; 1 from its own samples; 14 are smaller than a sample and keep no level). The Caspian Sea, ocean-classified because the polygons leave it out of the lakes layer, is handled explicitly as an inland sea at the median of the land cells touching it (−26 m, 38,768 cells). The Black Sea stays ocean at 0 m: the 2′ grid does not resolve the Bosphorus.
- **Land floor:** land-classified source samples are clamped to **−440 m** before averaging (18,230 samples, in fjords and atolls where the 10m polygon is coarser than the DEM). Classification is unchanged and real depressions are above the floor. The lowest value in the bundle is −440 m.
- **Probe values (bundle vs real surface):** Superior 197 (183), Baikal 481 (456), Tanganyika 821 (773), Geneva 403 (372), Caspian −26 (−28), Titicaca 3,822 (3,812), Dead Sea water −362 (−430), Death Valley −85 (−86). Lakes in steep terrain sit 10–50 m above their true surface because the shore median includes hillside samples; the Dead Sea is 68 m high for the same reason. Acceptable for stylized relief; the card never draws or states lake heights.
- **Classification tolerance:** polygon fill is inclusive of edges, so a sample within about half a source sample (~460 m) of a coast may classify either way. Small unmapped lakes stay land (ADR).
- **Land cover:** `NE1_LR_LC` (3×3 source pixels per 4′ cell; a cell is "no cover", index 0, if most pixels are the pure-white blank, otherwise the mean of its non-white pixels) is quantized to a fixed 255-colour palette (deterministic weighted median cut, stored in the manifest; index 0 reserved).
- **Size report (actual, this build):** 200 tiles × 619,650 B = 123,930,000 B (elevation 111.237 MiB + water mask 6.95 MiB), land cover 14,580,000 B, manifest 42,933 B. **Installed total 138,552,933 B = 132.134 MiB** against the 140 MiB cap (7.87 MiB margin); elevation-only base grid 111.237 MiB. **Release zip `roadprint-terrain-v1.zip`: 25,806,517 B = 24.61 MiB**, sha256 `09f51d28…e58a6` (measured, not assumed; Apple's App Store compression will differ).
- **Land cover 4′ vs finer:** `previews.py` writes `brenner-landcover-4arcmin-vs-source.png` (4′ palette, bilinear as core looks it up, versus the source raster at its native 1.33′). The 4′ layer is smoother and no worse at card scale; the hillshade carries the detail. Recommendation: ship 4′, not the 55.62 MiB 2′ layer.
- **Dependencies (dataset prep and its tests only, not shipped):** numpy, tifffile, imagecodecs (decodes the DEFLATE/float GeoTIFF), pillow (polygon fill, PNG previews), pyshp (reads shapefiles), scipy (connected components for inland seas). All permissively licensed; pinned in `requirements.txt`.
- **Packaging (ADR 0001 Amendment 2):** the bundle is not committed. It is the deterministic `roadprint-terrain-v1.zip` attached to the GitHub pre-release `terrain-v1`, pinned by `Tools/terrain/bundle.lock.json` (tag, asset, bytes, sha256). `Tools/terrain/fetch_bundle.sh` downloads it with `gh`, verifies the checksum and unpacks it into `App/Resources/Terrain/` (git-ignored). Wiring the fetch into `ios-build` with `actions/cache` is [ROA-12](/ROA/issues/ROA-12).

**Credits (keep with the data; Settings must show this exact text, preserving the existing Natural Earth line and adding the land-cover raster):**

> Terrain derived from NOAA NCEI ETOPO 2022 30 Arc-Second Global Relief Model; resampled by RoadPrint. DOI 10.25921/fd45-gt74. Licence: CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/).
> Made with Natural Earth (vector map data and Natural Earth I land cover raster).

Elevation heights are EGM2008 metres above the geoid on WGS84; the card is stylized regional relief, not a navigation aid.
