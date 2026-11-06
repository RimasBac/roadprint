# Data format (export/import contract)

The export format is the cross-platform contract (AGENTS.md §7.3): GPX plus the versioned JSON below. This file is started in ROA-31; GPX writing, the full export envelope and migration notes come with the export milestone.

Swift types live in `RoadPrintCore/Sources/RoadPrintCore/Model/`. JSON is produced by `ExportJSON.encoder()`: keys sorted, **dates as ISO 8601 UTC with millisecond precision** (exactly three fractional digits, `2026-06-01T14:00:00.250Z`; readers also accept whole seconds, `2026-06-01T14:00:00Z`). Sub-millisecond parts of a timestamp are not kept, so a re-imported trip matches the original to the millisecond, not bit for bit, distances in metres, times in seconds, coordinates in degrees (WGS84).

**No speed by design.** Neither `TrackPoint` nor the JSON has a speed or course field, and none will be added (plan §4.2). Speed can't be recovered from the file beyond what timestamps and positions already imply.

## Trip (`schemaVersion` 1)

| Field | Type | Notes |
|---|---|---|
| `id` | UUID string | Stable, for merge and dedupe |
| `createdAt`, `updatedAt` | date | `updatedAt` is bumped on every write |
| `schemaVersion` | int | `1`. Readers must reject newer versions or migrate older ones |
| `status` | `"recording"` \| `"completed"` \| `"partial"` | `partial` = after processing: at least one unfilled gap (a jump ≥ 2 km that is not a filled tunnel gap, see ADR 0003). Short, slow gaps (≤ 15 min, ≤ 25 km, ≤ 45 m/s) are filled and the trip stays `completed` |
| `visibility` | `"private"` | The only value in v1 |
| `points` | `[TrackPoint]` | In time order |
| `endedAt` | date, optional | Set when ended. Absent while recording |
| `startedAt` | date, optional | Added in schema 2, see ADR 0003. Set from the first raw point |
| `summary` | `TripStats`, optional | Added in schema 2, see ADR 0003. `distanceMeters`, `movingTimeSeconds`, `elapsedSeconds`, `gapCount` |
| `route` | `ProcessedRoute`, optional | Added in schema 2, see ADR 0003. `segments[].points[]` of `latitude`, `longitude`, optional `altitude`. No time or accuracy. `points` is `[]` once a route exists |

Start time is the first point's `timestamp`; the end time is `endedAt`, else the last point's `timestamp`. Distance, moving time and the rest are derived from `points`, never stored.

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
