# ADR 0003: the processed trip

- Date: 2026-11-06
- Status: Accepted (CTO), [ROA-38](/ROA/issues/ROA-38), epic [ROA-19](/ROA/issues/ROA-19)

## Decision
- Raw `points: [TrackPoint]` exist only while recording, or until processing succeeds. `TripProcessor.process(_:) -> Trip` returns the trip with `points = []` and these optional fields set:
  - `summary: TripSummaryStats` (an alias of `TripStats`): distance, moving time, elapsed time and unfilled gap count, computed from the **full cleaned trace before trimming**, then stored. This is a one-time derivation from data that is then deleted, not a counter, so AGENTS.md §7b.5 still holds. Distance includes the straight line across filled gaps.
  - `route: ProcessedRoute?`: `segments: [RouteSegment]`, each a `[RoutePoint]` (`latitude`, `longitude`, `altitude?`). **`RoutePoint` has no timestamp and no accuracy**, so speed can't be derived from stored data (AGENTS.md §8). A break between segments is an unfilled recording gap, drawn dotted.
  - `startedAt` (JSON key `startedAt`, Swift `storedStartedAt`) is set from the first raw point. The computed `Trip.startedAt` falls back to the first point for unprocessed trips.
- Pipeline order: **clean → trim → simplify**. Trimming the dense trace is more accurate than trimming the simplified one. Later stages add `places` and `mainRoad` (separate issues). Each stage is a pure function and `TripProcessor` composes them.
- Export `schemaVersion` becomes 2 in the trim issue. Until then the new fields are optional and no app code writes them.

## Cleaning (`RouteCleaner`, thresholds in `ProcessingHeuristics`)
1. Drop points with `horizontalAccuracy < 0` or `> 100` m.
2. Drop spikes: implied speed from the last kept point `> 75` m/s (also drops duplicate or out-of-order timestamps). Exception: if the next 3 points are each reachable from the jumped-to point at `≤ 75` m/s, it is a real relocation. Keep it, and the jump becomes an unfilled gap.
3. Gaps (consecutive points `≥ gapMinDisplacement`, 2 km): a **filled tunnel gap** has duration `≤ 15` min, displacement `≤ 25` km and implied speed `≤ 45` m/s, and is joined by a straight line inside one segment. Any other gap splits the segments and the trip becomes `partial`. Speed is computed transiently and never stored.

## Simplification (`DouglasPeucker`)
Per segment, so segment endpoints stay. Tolerance 15 m by default, clamped to 10–30. Distance is point-to-segment in a local equirectangular projection (metres). `forceKeep` indices are always kept (the trim stage keeps the summit this way). Iterative, so 20k points are safe.

## Addendum (ROA-39): places

`TripProcessor` takes an optional `PlaceIndex` and runs `places(along:)` on the cleaned dense trace **before** trimming, so regions only the trimmed ends cross are still listed (coarse enough for privacy). The result is `Trip.places` (`TripPlaces`: ordered, de-duplicated countries and regions). Lookup uses the bundled `places.rpgeo` (`Tools/places/FORMAT.md`).

## Addendum (ROA-41): main road

`TripProcessor` takes an optional `RoadIndex` and sets `Trip.mainRoad` (`MainRoad`: `network`, `ref`, `countryCode`) by resampling the dense route every 250 m (per segment, gaps not bridged), matching each sample to the nearest bundled road within 150 m, and taking the `(network, ref)` with the most samples if they cover at least 15 % of the route length (ties: higher network rank). It runs on the dense route after trim, before simplification, so the trimmed ends cannot name the road; until the trim stage exists it uses the whole cleaned route. With an index and no match, `mainRoad` is cleared. Data: `roads.rpgeo` (`Tools/roads/FORMAT.md`).

