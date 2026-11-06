# roads.rpgeo, format version 1

Major-road polylines, read by `RoadIndex` in `RoadPrintCore`. Built by `Tools/roads/build.mjs` from Natural Earth 5.0.0 1:10m `roads` (country codes from 5.1.1 `admin_0_countries`).

All integers are **unsigned LEB128 varints** unless marked *zigzag* (`n >= 0 ? 2n : -2n - 1`, then varint). Coordinates are integers in units of 1e-5° (about 1.1 m).

```
magic        4 bytes   "RPRD"
version      1 byte    1
stringCount  varint
  per string: byteLength varint, UTF-8 bytes     (sorted, unique; refs and country codes)
roadCount    varint
  per road (sorted by network, ref, country, first vertex):
    network    1 byte    0 generic, 1 usInterstate, 2 usHighway, 3 canadaHighway,
                         4 eRoad, 5 ukMotorway, 6 ukARoad, 7 australia
    ref        varint    string index. "80", "E40", "M6", "A40", "SH1"
    country    varint    string index. ISO_A2_EH (NE ADM0_A3 where that is -99); "" if the road is in no outline
    partCount  varint
      per part (a polyline):
        pointCount varint   >= 2
        per point: dx zigzag, dy zigzag   (delta from the previous point; the first from (0, 0))
```

Rules:

- One road is one `(network, ref, country)` record with one or more polylines. Natural Earth splits long roads into many records; they stay separate.
- `network` and `ref` come from the table in `normalise.mjs` (tested by `normalise.test.mjs`). Roads without a usable ref (NE has 7,000 unnamed ones, mostly in Asia and all of Australia) are not in the file.
- The country is that of the outline holding the road's middle vertex (or, failing that, another sample vertex).
- Lines are simplified (Visvalingam, 40 m), so they stay well inside the 150 m match radius.
- Output is deterministic: records and strings are sorted, and there are no timestamps.

Readers must reject files with an unknown version.
