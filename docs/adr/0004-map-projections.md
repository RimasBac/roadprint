# ADR 0004: fitted spherical map projections

Accepted for implementation in ROA-50; 2026-11-10. Plan §5.3.

`RoadPrintCore` projects into east/north metres on a sphere of radius
6,371,008.8 m. A sphere keeps the shared drawing math small; ellipsoidal survey
accuracy is unnecessary for these maps. Europe uses the 52° N, 10° E origin
of EPSG:3035, with no false offsets; this spherical result is **not** EPSG:3035.
CONUS uses Albers (29.5°/45.5° parallels, 23° N/96° W origin). Local trips use
LAEA at the bounds centre. Global views use Robinson's five-degree Snyder
table with linear interpolation, centred on the unwrapped sample mean longitude.

The chooser checks size first, then CONUS, then Europe, then global. All chooser
thresholds are documented constants in `ProjectionChooser.swift`:

| Constants | Value | Meaning |
|---|---|---|
| `localSpanMeters` | 2,500,000 m (strictly below) | Largest of meridional arc and parallel arc at bounds centre |
| `conusSouth`, `conusNorth` | 24°, 50° | Inclusive latitude bounds |
| `conusWest`, `conusEast` | −125°, −66° | Inclusive longitude bounds |
| `europeSouth`, `europeNorth` | 35°, 72° | Inclusive latitude bounds |
| `europeWest`, `europeEast` | −25°, 45° | Inclusive longitude bounds |

Perth–Adelaide uses local LAEA: its parallel-arc width at the bounds centre is
about 2,110 km, below 2,500 km. Kaunas–Verona also uses local LAEA; Lisbon–Helsinki
uses Europe. Alaska/Hawaii trips use local LAEA when small and global otherwise.
Longitude bounds exclude the largest circular gap; Fiji–Samoa spans 10.2°.
Sorting before summing makes the unwrapped mean independent of input order.

`ViewportFit` preserves aspect, flips y, respects insets and centres the bounds.
The limiting viewport axis fills exactly unless the default 50,000 m minimum
largest span or caller's maximum scale limits zoom. A 2 km horizontal trip occupies
4% of the available width. Degenerate points centre within a 50 km square.
Invalid fits return nil. Projection inputs reject non-finite values, clamp
latitude to ±89.9° and wrap longitude to [−180°,180°). LAEA clips the far hemisphere;
Robinson has no inverse. Origin trigonometry and Albers constants are cached.

Reference fixtures come from pinned proj4js 2.22.0 (1 m tolerance; Robinson 0.1%
of equatorial width because proj4js uses cubic interpolation). Six-decimal golden
fixtures use proj4js for LAEA/Albers and Snyder linear interpolation for Robinson;
Linux and iOS simulator tests compare these at 1e-6 m. Seeded round trips cover
1,000 points per invertible kind at 1e-7°. Linux CI measures 100,000 projections
per kind in **release**, enforcing <50 ms and printing the measured times.

Sources: [Snyder, USGS PP 1395](https://pubs.usgs.gov/pp/1395/report.pdf),
[proj4js](https://github.com/proj4js/proj4).
