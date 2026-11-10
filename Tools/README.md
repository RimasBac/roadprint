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

## design/gen-tokens.mjs

Generates `App/Design/Tokens.generated.swift` from `Design/tokens.json`, including dynamic sRGB night/day colours, launch-screen colour assets, fixed card palettes, type, spacing, motion and theme drawing rules. No npm dependencies. The `terrain` group is validated but not emitted: the app has no Terrain consumer yet.

```
node Tools/design/gen-tokens.mjs
node --test Tools/design/gen-tokens.test.mjs
node Tools/design/check-app-literals.mjs
```

Linux CI checks contrast (all text surfaces in both themes, minimum 4.5:1), references, token types, determinism and stale output. The literal checker scans app Swift files; exceptions require an exact path, exact source line and written reason in `Tools/design/literal-allowlist.json`. Keep the list empty when possible. Sheet radius uses the system default; `RPSize.hairline(displayScale:)` takes the view's display scale so one pixel stays one pixel.

### Bundled font credits

Inter by the Inter Project Authors and Barlow Condensed by Jeremy Tribby are licensed under the SIL Open Font License 1.1. Full licences are in `App/Resources/Fonts/Inter/OFL.txt` and `App/Resources/Fonts/BarlowCondensed/OFL.txt`, included in the app bundle for future Settings credits. Source: [Inter](https://github.com/rsms/inter), [Barlow](https://github.com/jpt/barlow), distributed by [Google Fonts](https://github.com/google/fonts) via its CSS API (`Tools/design/fetch-fonts.mjs`). No runtime download.

The committed files are full, static TTFs: Inter Regular, Medium, SemiBold and Bold; Barlow Condensed SemiBold and Bold. `Fonts/manifest.json` records their SHA-256 and PostScript names. `Font.rpNumber` and `RPType.statNumber` enable tabular figures with `.monospacedDigit()`, so changing digits do not move the stats row. `RoadPrintTests/DesignFontTests.swift` verifies registration, generated type rendering and equal digit advances on the simulator.

The DEBUG-only gallery launches with `-RPTokensGallery YES`; test launch flags `-RPDebugTheme day|night` and `-RPDebugAX3 YES` select screenshot variants. Release follows system appearance. `TokensGalleryScreenshotTests` attaches overlapping pages of every swatch, type style and button state in both themes, default size and AX3, plus Home in day with replayed trip digits. Pressed gallery samples reuse the production button surface. Press feedback uses the fast animation; Reduce Motion removes scale while retaining the opacity cross-fade. There are no new haptics. Device checks remain button feel, animation timing and scrolling smoothness.
