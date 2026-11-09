# ADR 0001: offline Terrain share card

- Date: 2026-11-06
- Status: Accepted (CTO). Amended 2026-11-09 for terrain style 3; see Amendment 1.
- Owner: CTO. Decision-only spike [ROA-8](/ROA/issues/ROA-8), requested by [ROA-6](/ROA/issues/ROA-6).
- Scope: visualization milestone 4b; no production code, new dependencies, data download service or iOS prototype in this change.

## Decision

Bundle a **2-arc-minute global heightfield derived from NOAA ETOPO 2022 ice-surface elevations**. Render an orthographic, oblique 2.5D hillshaded relief with a projected amber route ribbon and highest recorded point. `RoadPrintCore` computes all geometry, sampling, shading, visibility and layout; SwiftUI Canvas draws the resulting primitives. Export at exactly 1080×1920 in sRGB.

Use a single pinned dataset and renderer version for every installation. No online elevation, map tiles, route-derived requests or automatic region downloads. The card works from first launch in airplane mode. This is stylized regional relief, not a road-level terrain model or navigation aid.

Product context:Product context: the [ROA-7](/ROA/issues/ROA-7) plan update (PR #1) added Terrain to §§3, 4.4, 5.2, 5.4, 5.5 (4b) and 13, and this ADR answers open decision 4 in §13. The existing [share-card mockup](../plan/mockups/2-share-cards.png) sets colour, typography and hierarchy. It is not an approved Terrain composition. Implementation stays in backlog until milestone 4 starts.ffs and size budget

Raw-size estimates below are **our calculations**, not provider download sizes. For spacing `s` arc-seconds, a cell-centred global rectangle needs `(360×3600/s) × (180×3600/s) × 2` bytes for signed 16-bit metre elevations. MiB means 2²⁰ bytes; no compression, tile headers or duplicate edges are included.

| Source | Resolution and coverage | Raw global rectangle | Assessment |
| --- | --- | --- | --- |
| ETOPO 2022 | 15″ native (~463 m north–south); 30″ and 60″ products; land and oceans worldwide | 15″: 6.95 GiB; 30″: 1.74 GiB; 60″: 445 MiB | Choose: global coverage, EGM2008 vertical datum, CC0; ice-surface variant gives visible surface over ice |
| GMTED2010 | 7.5″, 15″, 30″ (~232–927 m); coverage varies by product, including polar limitations | 7.5″: 27.81 GiB; 15″/30″ as above | Public domain, mostly EGM96 with source variations; less uniform coverage/datum and no advantage after coarse resampling |
| Copernicus GLO-90 | Nominal 3″/~90 m global land DSM, includes vegetation/buildings | Uniform rectangular upper estimate 173.81 GiB; actual tiled delivery differs | EGM2008; detailed but unnecessary for this overview. Licence permits reuse with prescribed attribution and redistribution conditions; more obligations than CC0 |

Provider evidence: [NOAA product](https://www.ncei.noaa.gov/products/etopo-global-relief-model), [NOAA metadata and CC0](https://www.ncei.noaa.gov/access/metadata/landing-page/bin/iso?id=gov.noaa.ngdc.mgg.dem%3Aetopo_2022), [ETOPO user guide](https://www.ngdc.noaa.gov/mgg/global/relief/ETOPO2022/docs/1.2%20ETOPO%202022%20User%20Guide.pdf), [USGS product](https://www.usgs.gov/centers/eros/science/usgs-eros-archive-digital-elevation-global-multi-resolution-terrain-elevation), [GMTED report](https://pubs.usgs.gov/of/2011/1073/pdf/of2011-1073.pdf), [Copernicus product](https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM), [Copernicus licence](https://dataspace.copernicus.eu/sites/default/files/media/files/2025-06/copernicus_contributing_mission_data_access_v2_cop_dem_licenses.pdf).

The chosen grid is **10,800×5,400×2 = 116,640,000 bytes = 111.24 MiB**. Its north–south spacing is about 3.7 km; east–west spacing shrinks with latitude. A 4′ alternative is 27.81 MiB but is expected to lose more Alpine relief (not yet visually measured); 1′ is 444.95 MiB before compression. Choose 2′ as the initial fidelity/size compromise, with a **120 MiB installed terrain-data cap** and **200 MiB target for the complete installed app**. These are proposed engineering budgets, not measured archive sizes or App Store limits. No compression saving is required to fit the terrain cap; distribution compression is a bonus. Fonts, other data and binary have the remaining app budget. Report installed and compressed sizes separately.

`Tools/` will pin the exact source release, URLs, checksums and licence text. Resample ice-surface heights with area-weighted low-pass aggregation, round deterministically to signed integer metres, and record pixel-centre registration, WGS84 coordinates, EGM2008 heights, scale, no-data sentinel, byte order and source version in a manifest. Use independently readable tiles without duplicate border samples; carry a land/water mask for coastal aggregation and water rendering. Derive the mask from the same pinned public-domain Natural Earth land and lake polygons as the bundled map; record release, scale, checksums and existing attribution in the terrain manifest. Classify source sample centres by polygon containment, never elevation sign. Aggregate land samples separately from water; classify a mixed output cell by majority area (land wins ties), keeping the land aggregate when classified as land. Ocean renders at sea level; mapped inland water retains aggregated surface elevation. Retain negative land elevations. Small unmapped lakes inherit coarse land classification, a documented limitation. Ocean bathymetry is not drawn as land. Missing data stays missing, never silently zero. Keep no-data/mask/index overhead within the cap and check totals in Linux CI.

This spacing cannot reconstruct narrow valleys, bridges or tunnel roofs. Validate Brenner, I-80 and Nullarbor crops before committing to the final style. If the board finds relief too coarse, reopen this ADR for a larger bundle or fixed continent packs; do not silently add online fetching. Packs could be privacy-compatible when explicitly selected independent of trips, but introduce download/version/availability states and are deferred.

Credit in Settings and `Tools/README.md`: “Terrain derived from NOAA NCEI ETOPO 2022 15 Arc-Second Global Relief Model; resampled by RoadPrint.” Include source DOI `10.25921/fd45-gt74`, CC0 link and selected release. Preserve existing Natural Earth credit. Credit integration ships with the data, not as an unsupported claim that data is bundled today.

## Rendering decision

| Approach | Verdict |
| --- | --- |
| Oblique heightfield + Canvas | Selected. Fixed camera, light and core-generated geometry suit one static image, portable tests and the dark visual system |
| Ridgeline-only Canvas | Possible later style, but less readable land surface; do not implement a second renderer now |
| SceneKit/RealityKit offscreen | Can render offline with the same data, but adds Apple-specific scene, GPU and export machinery for a static card. SceneKit is deprecated; RealityKit is unnecessary here |
| MapKit 3D snapshot | Reject for this card. Tile loading depends on the requested area and system content; cannot guarantee offline availability, a fixed terrain dataset or our visual style. Keep MapKit for the plan's separate zoom view |

Apple documents [Canvas drawing](https://developer.apple.com/documentation/swiftui/canvas), [snapshot tile loading](https://developer.apple.com/documentation/mapkit/mkmapsnapshotter) and [SceneKit deprecation](https://developer.apple.com/videos/play/wwdc2025/288/). The privacy/style conclusions above are architectural inferences from those capabilities.

Core builds a bounded resampled mesh, initially 160×160 vertices (~50,562 triangles), with a fixed triangulation and deterministic stable order. Compute normals and directional hillshade in core using explicit token inputs. Start with a fixed north-up azimuth and 45° viewing elevation; Designer tokens set the final camera and bounded vertical exaggeration. Apply the same vertical transform to the route and land. Fit the entire permitted route with padding; enforce a minimum 100 km terrain footprint so tiny trips do not imply invented detail.

Projection must reuse the core's approved trip/region projection policy, unwrap the antimeridian, handle polar routes, and use consistent metre units for horizontal and vertical axes. Large extents need a regional/global overview projection, not an unbounded local tangent plane. Projection choice, camera and scale are part of the versioned recipe. No device-size-dependent geometry or adaptive quality during export.

Resolve terrain occlusion in core with a bounded screen-space depth/visibility pass (including splitting overlapping projected primitives where required); centroid sorting alone is insufficient. Output an ordered draw list of 2D triangles, shaded colour indices, route paths, visible/occluded segment flags and label candidates. App draws paths and token-driven glow. The mesh and depth workspace are temporary, never synced.

“Identical” means the same data, scene geometry, framing, styles and export dimensions for the same summary, units, locale and recipe. Canvas/font antialiasing can differ by OS; do not promise byte-identical PNGs. Golden core geometry must match exactly after documented quantization; raster comparison uses a documented tolerance. If literal pixel identity becomes required, a versioned software rasterizer is a separate decision.

## Recorded altitude and privacy

The Terrain renderer consumes only the shared privacy-filtered `TripShareSummary` introduced by ROA-7: already trimmed/coarsened permitted geometry, altitude with provenance/quality, places and permitted stats. It never reads raw fixes or the full trip. Summit selection happens after privacy filtering and cannot resurrect a removed endpoint. No speed is added.

Recorded sensor altitude remains authoritative for ribbon Z and highest-point text. [Core Location altitude](https://developer.apple.com/documentation/corelocation/cllocation/altitude) is approximately mean-sea-level height, normally EGM2008; reject invalid vertical accuracy. [Barometer relative altitude](https://developer.apple.com/documentation/coremotion/cmaltitudedata/relativealtitude) is a change from the initial event, not an absolute elevation. Recording fusion anchors relative changes to valid absolute fixes, maintains quality/provenance and resets at gaps. That fusion is an upstream recording responsibility, not performed again differently by each card.

Do not confuse ellipsoidal and orthometric heights. Imported altitude with unknown datum stays marked unknown; do not silently convert or calibrate it against coarse DEM samples. ETOPO and usual iOS altitude have compatible nominal datum, but sensor error and DEM smoothing remain. **Never snap recorded heights to the DEM, shift the entire route to fit it, or alter persisted altitude/stats.**

Project the ribbon at recorded Z. Where coarse relief hides it, draw a subdued dashed x-ray segment at that same projected location; visible segments get the solid amber glow. Draw-order bias is a screen-space styling effect, not a metre offset. This handles coarse mountain mismatches without inventing a road surface. Keep known recording/tunnel gaps distinct from terrain occlusion in style metadata. Do not infer tunnels from DEM disagreement. Label the highest valid measured point as “Highest recorded point”; use a summit/pass name only when trusted offline enrichment establishes it. Exclude interpolated/invalid samples from that maximum.

Only absolute altitude with a known compatible mean-sea-level datum may participate in the terrain ribbon. Unknown/incompatible datum imports use the flat fallback unless an explicit, tested datum conversion has already occurred upstream. Within a usable route, split ribbon paths at invalid-altitude spans and show an unavailable-height gap; never interpolate across those spans for a summit or continuous measured ribbon. If valid absolute altitude is unavailable, use the existing flat card layout with “Elevation unavailable”; do not misrepresent DEM height as recorded altitude. “Hide route” shows places and stats only: omit route, summit marker, profile and route-shaped terrain/camera crop. A generic background must not encode the hidden path. Derived render caches remain local, use privacy mode in their key, and are removed with trip deletion.

## Ownership and validation

| Layer | Responsibility and verification |
| --- | --- |
| `Tools/` — Platform | Reproducible DEM prep, manifest, credit and size report; Linux script tests for sentinel/masks, coastlines, borders, checksum determinism and byte budget |
| `RoadPrintCore/` — Platform | Foundation-only DTOs, tile decode, sampling, projections, mesh, hillshade, visibility, route/altitude rules and label layout; Linux `swift test` fixtures for seams, poles, negative land, missing heights, occlusion, trimmed maxima and hide-route |
| `Design/` — Designer | Tokens, original terrain card composition and PNG previews; board approves card style |
| `App/` — iOS Engineer | Local resource loading, protocol adapter, Canvas draw list, bundled fonts, String Catalog, Pro entitlement, Settings credit, fixed-size export; macOS CI build and simulator PNG artifacts |

Estimated iPhone 12-class **release-mode** export: 0.05–0.2 s tile sampling; 0.1–0.4 s geometry/visibility; 0.2–0.8 s drawing/glow; 0.1–0.4 s PNG encoding: roughly **0.5–2 seconds**, with a provisional p95 target ≤2 s and ≤80 MiB incremental peak memory. These are workload estimates, not measurements. One RGBA output alone is 7.91 MiB; bound intermediates and read tiles on demand rather than decoding the whole globe. Cache by summary hash, privacy mode, dataset/renderer/token versions, locale and units.

Validate 30 warm and 10 cold exports for each reference route. Simulator CI verifies correctness and images, not iPhone 12 timing. The board supplies real-device benchmark results through the normal TestFlight path; only the CTO dispatches that workflow. If targets fail, reduce unnecessary draw work or revisit the recipe in a new version; never silently lower quality per phone. This spike ran no Swift/iOS builds and makes no measured performance claim. No prototype image was needed to select the architecture; the first real-data preview is an explicit implementation gate.

## Designer handoff

Provide `terrain.*` entries in `Design/tokens.json`, with generated Swift constants: land ramp stops/positions, water/background, hillshade light direction and ambient/diffuse factors, camera azimuth/elevation, vertical exaggeration bounds; ribbon width, amber colour, glow radii/opacities, occluded/gap dash styles; summit marker size, leader stroke, label spacing, contrast and typography. Reuse plan §5.1: background `#14161c`, land `#1d2029`, amber `#ffb547`, text `#f0efec`, secondary `#a6aab4`, Inter and Barlow Condensed.

Deliver SVG composition/template and 1080×1920 PNG previews for I-80 and Brenner, plus flat terrain, altitude-unavailable and hide-route variants. Express sizes in export pixels; include safe areas and long/localized-label examples. The iOS engineer integrates approved assets; visual values never live as ad hoc constants in feature code. Geometry limits and quality thresholds remain engineering configuration, not colour tokens.

## Amendment 1 (2026-11-09): terrain style 3

The board rejected two grey relief rounds in [ROA-11](/ROA/issues/ROA-11). Style 3 ([PR #15](https://github.com/RimasBac/roadprint/pull/15), `Design/cards/terrain/`) adds natural ground colour. Board approval of style 3 must be recorded on ROA-11 before [ROA-12](/ROA/issues/ROA-12) starts. Everything above still applies, except for these changes.

**Ground colour layer.** The ground colour comes from Natural Earth I land cover (`NE1_LR_LC`, public domain), graded by `terrain.landCover` tokens. It ships as a second bundled raster, not RGB:
- 8-bit palette indices on a **4′ grid** (5,400×2,700 = 14,580,000 bytes = 13.90 MiB raw). There is one fixed 256-entry palette. `Tools/` builds it deterministically from the pinned source and records it in the terrain manifest. Index 0 is reserved for "no land cover".
- Core looks up the palette, interpolates colour per vertex and applies the grade and hillshade. The app only fills the coloured triangles core returns.
- Land cover is smooth at card scale; the 2′ elevation and hillshade carry the detail. ROA-9 must produce a 2′ vs 4′ comparison of the Brenner preview. If the 4′ version is visibly worse, stop and reopen this amendment; do not ship the 55.62 MiB 2′ layer by default.

**Size budget, replacing the 120 MiB terrain cap.** Elevation 111.24 MiB + land cover 13.90 MiB + 1-bit 2′ land/water mask (7,290,000 bytes = 6.95 MiB) = **132.09 MiB raw**. The new installed terrain-data cap is **140 MiB**, which includes tile indexes and the manifest. The 200 MiB whole-app target is unchanged. Linux CI checks the totals.

**Mesh.** The default is **240×240 vertices** (114,242 triangles), up from 160×160, which showed a 7 px triangle staircase. Geometry and visibility work grows by about 2.3×. The revised estimate on an iPhone 12-class phone is **0.6–2.5 s**; the p95 target stays ≤2 s. ROA-10 reports the core timing on Linux as a proxy. If the device benchmark misses the target, fall back to 200×200 in a new recipe version, never per device.

**Hide route.** The relief is framed on the summary's named places only: the bundled place-index centre points carried in `TripShareSummary`, never trip points, trimmed endpoints or a route bounding box. Each place gets a pin and its name. There is no route, route light, summit marker or profile. Framing uses `terrain.hiddenRoute.framePadding` and the 100 km minimum footprint. With one place, centre on it. With none, use the generic flat layout. The highest recorded altitude may appear as a number among the stats. This replaces the earlier "generic background" rule. The frame reveals nothing the place names don't already show.

**Altitude unavailable.** This replaces the "existing flat card layout" fallback with the land-cover colour on a flat plane: no relief exaggeration, no hillshade, no summit, and the "Elevation unavailable" notice. The route is drawn at plane height and is never draped on DEM heights.

**Preview-only sources.** `Tools/design/` previews use AWS Terrain Tiles and OSRM demo routes (© OpenStreetMap contributors, ODbL). They are git-ignored, never shipped and need no in-app credit. The shipped data stays ETOPO 2022 plus Natural Earth. The Settings and `Tools/README.md` credits add "Natural Earth I land cover raster" to the existing Natural Earth line.

**Tokens versus configuration.** Camera, exaggeration and colour grading stay in `Design/tokens.json`. The mesh size, the depth-buffer resolution and the size caps are core configuration, versioned with the recipe.

## Follow-up work

Created backlog issues: [ROA-9: DEM preparation](/ROA/issues/ROA-9) and [ROA-10: core scene computation](/ROA/issues/ROA-10) assigned to Platform; [ROA-11: tokens/compositions](/ROA/issues/ROA-11) assigned to Designer; [ROA-12: integration/export](/ROA/issues/ROA-12) assigned to iOS Engineer. Every issue carries goal, acceptance criteria, folders and verification. Core depends on the DEM format; iOS depends on core and approved design. These future tasks do not block closure of the decision spike once its ADR merges.
