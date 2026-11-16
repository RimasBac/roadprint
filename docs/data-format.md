# Data format (export/import contract)

The export format is the cross-platform contract (AGENTS.md §7.3): GPX plus the versioned JSON below. This file is started in ROA-31. The export envelope and GPX writing are below (ROA-75); import merging comes next.

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
| `mainRoad` | `MainRoad`, optional | Added in schema 2. `{network, ref, countryCode}`. `network` is one of `usInterstate`, `usHighway`, `canadaHighway`, `eRoad`, `ukMotorway`, `ukARoad`, `australia`, `generic`; `ref` is the number as the sign shows it (`80`, `E40`, `M6`). `countryCode` may be absent. Absent if no bundled road covers at least 15 % of the route or the processor had no road index |

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
- It is measured along the cleaned path (filled gaps count as straight lines, an unfilled gap counts as the straight chord from the last point of one segment to the first of the next) and the cut is interpolated to the exact distance.
- `start` and `end` are centred on the first and last retained point with radius = trim distance. If a cut falls inside an unfilled gap, the retained end is the edge of the next segment and the radius is the path distance to it (more than the trim distance). Straight-line distance never exceeds path distance, so the real endpoints are inside their circles.
- **Short trip:** if the path is ≤ 2 × trim + 2 km, nothing is stored but one circle: `segments` is `[]`, `start` equals `end`, centred at the point half way along the path (this point can lie in a gap, on the chord), radius = max(trim, path / 2).
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

## TripShareSummary (`schemaVersion` 1)

Not part of export; future feed payload. Built only by `TripShareSummary.make(from:options:)`, the single privacy filter; share cards render only from it.

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | int | 1 |
| `tripID` | UUID string | |
| `day` | `{year, month, day}` | Calendar date of the start in the chosen time zone; no time of day |
| `distanceMeters`, `movingTimeSeconds` | double | |
| `places` | object | `countries`, `regions` |
| `mainRoad` | object? | |
| `badgeIDs` | string[] | Empty until M7 |
| `summitAltitudeMeters` | double? | Whole metres |
| `route`, `start`, `end`, `summit` | optional | Only if the user shares the route. Douglas–Peucker 50 m, coordinates rounded to 1e-4°, altitude to whole metres; no timestamps, accuracy or speed |

## UserProfile

| Field | Type | Notes |
|---|---|---|
| `id` | UUID string | Local user ID, no account |
| `displayName` | string | |
| `distanceUnit` | `"kilometers"` \| `"miles"` | Display only; all stored distances are metres |
| `startingCareerDistanceMeters` | double | Distance driven before RoadPrint |
| `createdAt`, `updatedAt` | date | |

## Export archive (`archiveVersion` 1)

**JSON is the restore format. GPX is for other apps and has no times for processed trips.** Written with `ExportJSON.encoder()`, read with `TripArchive.decode(_:)`. Swift: `TripArchive`, `ArchiveError`, `ExportFileNames` (`Model/TripArchive.swift`).

| Field | Type | Notes |
|---|---|---|
| `format` | string | Always `"roadprint-archive"`. A reader rejects anything else (`ArchiveError.notARoadPrintFile`) |
| `archiveVersion` | int | `1`. A reader rejects a larger value (`ArchiveError.newerVersion`) |
| `exportedAt` | date | Millisecond ISO 8601 UTC |
| `appVersion` | string | App version and build, e.g. `"1.0 (15)"`. Informational |
| `profile` | `UserProfile`, optional | See below |
| `trips` | `[Trip]` | Every status (`recording`, `completed`, `partial`), schema 1 and 2 mixed, newest start first. A trip with a `schemaVersion` above 2 also gives `newerVersion`. Not JSON or damaged gives `ArchiveError.corrupt` |

`RoadPrint-YYYY-MM-DD.json` and `.gpx` name the files, dated in UTC from the export date. `Fixtures/archive-v1.json` is frozen: every later version must keep reading it.

### GPX mapping (`GPXWriter`)

GPX 1.1, one document for many trips, one `<trk>` per trip with `<name>` = the start time (`2026-06-01T14:00:00Z`) and no `<extensions>`.

| Trip | Output |
|---|---|
| Processed (schema 2) | One `<trkseg>` per `route.segments[]`. `<trkpt lat lon>` with `<ele>` when known. **No `<time>`**: the stored route has none |
| Raw (schema 1: recording or not yet processed) | One `<trkseg>` with every point, `<ele>` and `<time>` (millisecond ISO 8601) |
| Short trip (`segments` empty) or no points | No `<trk>` |

Never speed or course. Text is XML-escaped; coordinates have 7 decimals, elevations 1. The file can't restore a trip: use the JSON for that.

## Import and merge rules (`TripImporter.plan`)

`TripImporter.plan(data:fileName:existing:localProfile:)` reads a file by content (first character `{` = JSON, `<` = GPX, else `notARoadPrintFile`) and returns an `ImportPlan` without writing anything. The app shows the counts, then saves `toInsert` and `toReplace`.

| File | Rule |
|---|---|
| Archive JSON | Each trip is matched to a stored trip by `id`. Not stored: `toInsert`. Stored, and the file's `updatedAt` is newer: `toReplace`. Stored, and the local `updatedAt` is the same or newer: `alreadyHere`. A stored trip that is still `recording` is never replaced. Duplicate ids inside one file: the newest `updatedAt` wins |
| Single trip JSON | An object with `id` and `schemaVersion` (no `format`) is treated as an archive of one trip |
| `status: recording` in the file | Skipped (`recording`). An in-progress trip is never imported |
| GPX from another app | Each `<trk>` with 2 or more timestamped points becomes a new schema 1 trip: new UUID, `createdAt` = `updatedAt` = now, `status` completed, `endedAt` = last time, `visibility` private, `points` from the file (accuracy 5 m, no speed). `plan.needsProcessing` is true: the app runs `TripProcessor` before saving so the privacy trim applies |
| GPX skips | Fewer than 2 timestamped points: `noTimes` (a RoadPrint GPX export has none: the preview says to pick the `.json`, see `suggestsJSON`). Path under 100 m: `tooShort` |
| GPX twice | A track whose start is within 2 s of a stored trip's start counts as `alreadyHere` |
| Profile | The file's `profile` is offered in `plan.profile` only if the local profile is still the default (empty `displayName` and `startingCareerDistanceMeters` 0). Otherwise the local profile stays |

Errors (`ImportError`, each has a plain `message` for alert A10): `newerVersion` (archive or trip written by a newer RoadPrint), `notARoadPrintFile`, `corrupt` (truncated or damaged JSON/XML), `empty` (no data, or no trips in the file). Importing the same file twice inserts nothing the second time.
