# Data format (export/import contract)

The export format is the cross-platform contract (AGENTS.md §7.3): GPX plus the versioned JSON below. This file is started in ROA-31; GPX writing, the full export envelope and migration notes come with the export milestone.

Swift types live in `RoadPrintCore/Sources/RoadPrintCore/Model/`. JSON is produced by `ExportJSON.encoder()`: keys sorted, **dates as ISO 8601 UTC with millisecond precision** (exactly three fractional digits, `2026-06-01T14:00:00.250Z`; readers also accept whole seconds, `2026-06-01T14:00:00Z`). Sub-millisecond parts of a timestamp are not kept, so a re-imported trip matches the original to the millisecond, not bit for bit, distances in metres, times in seconds, coordinates in degrees (WGS84).

**No speed by design.** Neither `TrackPoint` nor the JSON has a speed or course field, and none will be added (plan §4.2). Speed can't be recovered from the file beyond what timestamps and positions already imply.

## Trip (`schemaVersion` 1 or 2)

| Field | Type | Notes |
|---|---|---|
| `id` | UUID string | Stable, for merge and dedupe |
| `createdAt`, `updatedAt` | date | `updatedAt` is bumped on every write |
| `schemaVersion` | int | `1` for a trip that still has raw `points` (recording or just ended), `2` once `TripProcessor` has run (trimmed `route`). Readers accept 1 and 2 and **reject anything newer** |
| `status` | `"recording"` \| `"completed"` \| `"partial"` | `partial` = after processing: at least one unfilled gap (a jump ≥ 2 km that is not a filled tunnel gap, see ADR 0003). Short, slow gaps (≤ 15 min, ≤ 25 km, ≤ 45 m/s) are filled and the trip stays `completed` |
| `visibility` | `"private"` | The only value in v1 |
| `points` | `[TrackPoint]` | In time order |
| `endedAt` | date, optional | Set when ended. Absent while recording |
| `startedAt` | date, optional | Added in schema 2, see ADR 0003. Set from the first raw point |
| `summary` | `TripStats`, optional | Added in schema 2, see ADR 0003. `distanceMeters`, `movingTimeSeconds`, `elapsedSeconds`, `gapCount` |
| `route` | `ProcessedRoute`, optional | Added in schema 2, see ADR 0003. `segments[].points[]` of `latitude`, `longitude`, optional `altitude`. No time or accuracy. Also `start`, `end`, `summit`, see below. `points` is `[]` once a route exists |
| `places` | `TripPlaces`, optional | Added in schema 2. `countries[]` and `regions[]` of `{code, name}`, in order of first visit, no repeats. Country code is ISO 3166-1 alpha-2 (Natural Earth `ISO_A2_EH`, A3 for a few disputed areas), region code is ISO 3166-2. A place counts only if at least 2 consecutive points (or at least 1 km) fall in it. Computed from the cleaned trace before trimming. Absent if the processor had no place index |

Start time is the first point's `timestamp`; the end time is `endedAt`, else the last point's `timestamp`. Distance, moving time and the rest are derived from `points`, never stored.

### Route (schema 2)

| Field | Type | Notes |
|---|---|---|
| `segments` | `[{points: [RoutePoint]}]` | Trimmed and simplified. A break between segments is an unfilled gap (drawn dotted). **Empty for a short trip** |
| `start`, `end` | `ApproximateArea`, optional | `{centerLatitude, centerLongitude, radiusMeters}`. The real start or end always lies inside |
| `summit` | `RoutePoint`, optional | Highest retained point after trimming (needs altitudes). Always kept by the simplifier |

`RoutePoint` is `latitude`, `longitude`, optional `altitude`. There is no `timestamp`, `speed` or `horizontalAccuracy` anywhere in `route`.

**Privacy trim** (plan §4.3, ADR 0003; pipeline order: clean → trim → simplify):

- Trim distance = 8,000 m + a deterministic offset in [0, 2,000) m: the 64-bit FNV-1a hash of the trip UUID's 16 bytes, top 53 bits divided by 2^53, times 2,000. The same distance applies to both ends of a trip. The offset blurs the ring of trip ends around home across many trips.
- It is measured along the cleaned path (filled gaps count as straight lines, unfilled gaps add no length) and the cut is interpolated to the exact distance.
- `start` and `end` are centred on the first and last retained point with radius = trim distance. Straight-line distance never exceeds path distance, so the real endpoints are inside their circles.
- **Short trip:** if the path is ≤ 2 × trim + 2 km, nothing is stored but one circle: `segments` is `[]`, `start` equals `end`, centred at the point half way along the path, radius = max(trim, path / 2).
- `summary` and `places` come from the full cleaned trace, before trimming.

Example (processed, abridged):

```json
{
  "createdAt" : "2026-06-01T14:00:00.000Z",
  "endedAt" : "2026-06-01T14:18:00.000Z",
  "id" : "6C0E4F9A-1B7D-4C8E-9A52-0D3F5E7A1B22",
  "points" : [],
  "route" : {
    "end" : { "centerLatitude" : 40.912, "centerLongitude" : -111.21, "radiusMeters" : 8421.7 },
    "segments" : [ { "points" : [
      { "altitude" : 1620, "latitude" : 40.8214, "longitude" : -111.7142 },
      { "altitude" : 1795, "latitude" : 40.912, "longitude" : -111.21 }
    ] } ],
    "start" : { "centerLatitude" : 40.8214, "centerLongitude" : -111.7142, "radiusMeters" : 8421.7 },
    "summit" : { "altitude" : 1795, "latitude" : 40.912, "longitude" : -111.21 }
  },
  "schemaVersion" : 2,
  "startedAt" : "2026-06-01T14:00:00.000Z",
  "status" : "completed",
  "summary" : { "distanceMeters" : 29836.1, "elapsedSeconds" : 1080, "gapCount" : 0, "movingTimeSeconds" : 1074 },
  "updatedAt" : "2026-06-01T14:18:00.000Z",
  "visibility" : "private"
}
```

A schema 1 fixture is in `RoadPrintCore/Tests/RoadPrintCoreTests/Fixtures/trip-v1.json`.

### TrackPoint

| Field | Type | Notes |
|---|---|---|
| `latitude`, `longitude` | double | Degrees |
| `altitude` | double, optional | Metres |
| `timestamp` | date | |
| `horizontalAccuracy` | double | Metres |
| `verticalAccuracy` | double, optional | Metres |

Example:

```json
{
  "createdAt" : "2026-06-01T14:00:00.000Z",
  "endedAt" : "2026-06-01T14:18:00.000Z",
  "id" : "6C0E4F9A-1B7D-4C8E-9A52-0D3F5E7A1B22",
  "points" : [
    {
      "altitude" : 1288.4,
      "horizontalAccuracy" : 5,
      "latitude" : 40.760157,
      "longitude" : -111.889808,
      "timestamp" : "2026-06-01T14:00:00.000Z",
      "verticalAccuracy" : 3
    }
  ],
  "schemaVersion" : 1,
  "status" : "completed",
  "updatedAt" : "2026-06-01T14:18:00.000Z",
  "visibility" : "private"
}
```

## UserProfile

| Field | Type | Notes |
|---|---|---|
| `id` | UUID string | Local user ID, no account |
| `displayName` | string | |
| `distanceUnit` | `"kilometers"` \| `"miles"` | Display only; all stored distances are metres |
| `startingCareerDistanceMeters` | double | Distance driven before RoadPrint |
| `createdAt`, `updatedAt` | date | |
