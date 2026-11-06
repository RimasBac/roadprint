# Tools

Data-prep scripts. Run on the server (Node or Python).

## fixtures/make-gpx.mjs

Builds GPX test fixtures for `RoadPrintCore` (and the iOS UI test replay) plus `expected.json`, which holds distance, moving time, gap and stop counts computed independently of the Swift code.

```
node Tools/fixtures/make-gpx.mjs
```

Output: `RoadPrintCore/Tests/RoadPrintCoreTests/Fixtures/` (`i80-ui-test.gpx`, `i80-long-stop.gpx`, `i80-gap.gpx`, `expected.json`). Output is deterministic; keep the thresholds at the top of the script in sync with `RecordingHeuristics.default`.

**Source and licence:** the geometry is the I-80 Salt Lake City → Sacramento route (`SLC-SAC`) in `docs/plan/mockups/source/routes.json`, routed with OSRM on OpenStreetMap data, © OpenStreetMap contributors, ODbL 1.0. Timestamps and altitudes are synthetic (about 100 km/h, 5 m altitude jitter).
