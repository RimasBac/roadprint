# RPTERR v1: bundled terrain format

All numbers little-endian. Registration is **cell-centred**: cell (row, col) of a W×H grid is centred at
`lon = -180 + (col + 0.5) · 360/W`, `lat = 90 − (row + 0.5) · 180/H`. Row 0 is north, col 0 starts at −180°.
Horizontal datum WGS84; heights are EGM2008 (above the geoid), signed int16 metres.

| File | Grid | Content |
| --- | --- | --- |
| `tNN_MM.rpt` (200: NN = tile row 00–09, MM = tile col 00–19) | 10,800 × 5,400 cells (2′) in 540 × 540 tiles (18° × 18°) | `540·540` int16 heights row-major (583,200 B), then the water bitmask (36,450 B): row-major, least-significant bit first, **1 = water** (ocean or mapped lake). Tile = 619,650 B, no header |
| `landcover-4arcmin.u8` | 5,400 × 2,700 cells (4′) | one uint8 palette index per cell, row-major, no header; **0 = no land cover** |
| `manifest.json` | n/a | version, grid, rules, sources and licences, SHA-256 and size of every file, the 256-entry RGB palette (index 0 reserved), size report |

- **No-data:** height `-32768` means the source had no valid height; never zero. (This build has none.)
- **Ocean cells** are `0` with the water bit set. **Mapped inland water** keeps its surface height with the water bit set. **Negative land** is kept (water bit clear).
- **No duplicated border samples:** tiles partition the grid. Readers wrap columns across the antimeridian (col 0 follows col 10,799) and clamp rows at the poles (no pole row; nearest centres are ±89.98333°).
- The land-cover grid shares the same corner and registration as the height grid, at half the resolution.
- `manifest.json` `version` is 1; any change to resampling, classification, palette method or layout bumps it.
- Reference reader: `rpterrain.Reader` (Python). The Swift reader in `RoadPrintCore` ([ROA-10](/ROA/issues/ROA-10)) must decode these tiles identically; use `tests/test_terrain.py::test_byte_order_and_bit_order` as the byte-layout spec.
