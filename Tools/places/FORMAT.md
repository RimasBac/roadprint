# places.rpgeo, format version 1

Compact country and admin-1 region outlines, read by `PlaceIndex` in `RoadPrintCore`. Built by `Tools/places/build.mjs` from Natural Earth 5.1.1 (1:10m `admin_0_countries` and `admin_1_states_provinces`).

All integers are **unsigned LEB128 varints** unless marked *zigzag* (`n >= 0 ? 2n : -2n - 1`, then varint). Coordinates are integers in units of 1e-5° (about 1.1 m).

```
magic        4 bytes   "RPGE"
version      1 byte    1
stringCount  varint
  per string: byteLength varint, UTF-8 bytes     (sorted, unique; codes, names, parent codes)
featureCount varint
  per feature (all countries first, then all regions; each group sorted by code):
    kind       1 byte    0 = country, 1 = region
    code       varint    string index. Country: ISO_A2_EH. Region: iso_3166_2
    name       varint    string index. English name
    parent     varint    string index. The country's code (equal to `code` for a country)
    minX, minY zigzag    bounding box corner, 1e-5° (lon, lat)
    width      varint    maxX - minX
    height     varint    maxY - minY
    ringCount  varint
      per ring:
        pointCount varint   >= 3. The ring is implicitly closed (no repeated first point)
        per point: dx zigzag, dy zigzag   (delta from the previous point; the first from (0, 0))
```

Rules:

- A feature's rings are all of its polygons' outer rings **and holes**, in one list. Readers use the **even-odd rule** over all rings of a feature, so holes and multipolygons need no marker.
- Geometry is cut at the antimeridian as in Natural Earth: parts touching ±180° end at exactly ±180°. There is no wrapping inside a ring, so a plain bounding box works.
- A country with `ISO_A2_EH` of `-99` (Somaliland, Northern Cyprus, ...) uses the Natural Earth `ADM0_A3` as its code. Regions whose `iso_3166_2` is a Natural Earth placeholder (`XK-X01~`, `-99-X..`) are left out; their country is still there.
- Rings narrower than about 1 km in both directions are dropped unless a feature would have none.
- Output is deterministic: features and strings are sorted, and there are no timestamps. The same input zips give a byte-identical file.

Readers must reject files with an unknown version.
