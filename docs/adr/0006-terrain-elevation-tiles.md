# ADR 0006: Terrain elevation from tiles for the trip's area

- Date: 2026-11-24
- Status: **Accepted by the board, 2026-11-24** (AWS tiles direct; the proxy in point 6 stays a later option). The CTO reviews the implementation PRs.
- Owner: Designer. Amends [ADR 0001](0001-terrain-card.md): elevation source, offline rule, mesh and renderer. Everything else in ADR 0001 and Amendment 1 still applies.
- Design: terrain style 5, `Design/cards/terrain/` (README and previews).

## Context

The board reviewed terrain style 4 on 2026-11-24 and asked for two things: the relief must fill the whole card, and it "lacks quality/resolution so looks cheap". Both come from the 2′ grid in ADR 0001. Its points are about 3.7 km apart, so at full-screen size a mountain range is a few dozen blurry quads. No offline grid that fits in the app fixes that: 1′ is 445 MiB raw and 30″ is 1.74 GiB (ADR 0001's own table), and even 30″ is coarser than the style-5 previews.

Style 5 previews use Terrarium elevation tiles at the zoom whose pixel matches the mesh spacing: z10 (104 m) for Brenner, z7 (938 m) for I-80, z6 for very long trips. The board then chose style 5 over a mock-up of the same card on Apple Maps satellite imagery (shown in review only; Apple imagery is not committed).

## Decision

1. **Elevation comes from tiles for the trip's area, fetched when the driver creates a Terrain card.** The source is AWS Terrain Tiles (Terrarium PNG, public dataset on the Registry of Open Data, no key). The app fetches through **one configurable base URL**, so a RoadPrint proxy (point 6) needs no app release.
2. **What is fetched:** the tiles covering the card's footprint at one zoom between 6 and 11, chosen so a tile pixel matches the mesh spacing, at most **160 tiles** (previews: about 3–13 MB per card). Tiles are cached on disk (LRU, 200 MB cap, purged on "Delete all data"), so re-sharing a trip is free.
3. **What the request reveals:** tile coordinates, so the region at 40–600 km granularity, plus the phone's IP address to the tile host. Never the route, times or trip points. The driver is about to publish a picture of that route, so the extra exposure is small, but it is new: `docs/privacy.html` must say it before this ships. Requests carry no identifiers, cookies or RoadPrint account data (there is none).
4. **Offline:** no blurry fallback. Without a connection the share sheet says "Terrain will be ready when you're back online" and offers the other cards. The card renders when tiles arrive. A Pro card that looks cheap hurts more than a short wait.
5. **The 2′ elevation bundle is dropped** (111.24 MiB of ADR 0001's 132.09 MiB). The Natural Earth land-cover palette (4′, 13.90 MiB) and the land/water mask (6.95 MiB) stay bundled: they are smooth at card scale and keep the colour offline-stable. The terrain-data cap becomes **25 MiB**.
6. **Proxy, later or from the start (board's choice):** a RoadPrint endpoint (for example a Cloudflare Worker with a cache) that forwards tile requests. The tile host then never sees the user's IP address, and both iOS and Android apps talk only to RoadPrint. Logging off, no request bodies. Costs one small service to run.
7. **Renderer:** style 5 draws about 1.1 million triangles (820×700 mesh) about 2 px tall. SwiftUI Canvas is not built for that. Core rasterises the draw list into an RGBA buffer itself (a small deterministic scanline rasteriser, painter's order far to near, 2× supersampling), and the app draws that one image plus the vector overlays (ribbon, labels, type) in Canvas. This keeps all terrain maths in Foundation-only `RoadPrintCore`, testable on Linux and portable to Android, and gives the byte-stable output ADR 0001 left as "a separate decision".
8. **Minimum footprint 60 km** (was 100 km): with real detail a short pass no longer needs to be padded with invented-looking blur.

## Options considered

| Option | Verdict |
| --- | --- |
| 2′ offline bundle (ADR 0001) | The board rejected the look. A finer bundle does not fit the app |
| Tiles for the trip's area, direct | **Chosen.** Same data as the previews; small, cached, portable to Android |
| Tiles through a RoadPrint proxy | **Later privacy upgrade** (point 6); same app code, different base URL |
| Region packs (Western US, Alps…) | Private and offline after download, but hundreds of MB each, awkward for long hauls, extra settings. Deferred |
| MapKit 3D satellite | Rejected again: Apple's look, not ours; no control of light, colour or occlusion; iOS-only, so Android would look different |
| Paid providers (Mapbox, MapTiler) | Keys, per-tile cost and caching limits; no gain over the open dataset |

## Risks

- **Availability:** the public bucket has no SLA. Mitigation: the base URL is configurable, the proxy can cache, and the cache keeps earlier cards working.
- **Data licence and credit:** Terrain Tiles combine several sources (SRTM, GMTED, ETOPO1, national DEMs and others) with their own attribution lines. Add them to the Settings credits and `Tools/README.md`; check the current attribution list before release.
- **Size per card on cellular:** 3–13 MB per new card in the previews. The tile budget is engineering configuration; lower it if real use shows it matters.
- **Recorded altitude versus finer DEM:** finer relief makes the ribbon's recorded altitude look more often "inside" a ridge. The depth bias (10 px) and the dashed x-ray rule from ADR 0001 stay. Re-check the occluded share on Brenner with real recorded altitude.
- **Performance:** estimate, not a measurement: tile decode 0.1–0.3 s, mesh and light 0.3–0.8 s, rasterising 0.3–1 s on an iPhone 12-class phone. The ≤2 s p95 target stays (excluding download time).

## Work

- **ROA-9** (DEM preparation) shrinks to: the land-cover palette, the mask and the terrain manifest. No elevation bundle.
- **ROA-10** (core scene) adds: tile fetching behind a protocol (the app provides the networking), zoom choice and tile budget, Terrarium decoding, the screen-uniform perspective mesh, the rasteriser.
- **ROA-12** (iOS integration) adds: the offline state in the share sheet, the cache and its purge, the privacy text, the credits.
- `docs/privacy.html` and the App Store privacy answers: describe the tile requests.
