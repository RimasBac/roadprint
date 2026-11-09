"""RoadPrint offline terrain format (RPTERR v1): shared library.

Pure functions (numpy only) so they can be tested with tiny fixtures.
Format and rules: see Tools/README.md ("Terrain bundle") and docs/adr/0001-terrain-card.md.
"""
import hashlib
import json
import numpy as np

FORMAT = "RPTERR"
VERSION = 1
NODATA = -32768            # int16 sentinel: source had no valid height. Never zero.
GRID_COLS, GRID_ROWS = 10800, 5400   # 2 arc-minute cells, cell-centred, global
TILE_COLS, TILE_ROWS = 540, 540      # 18 x 18 degrees; 20 x 10 tiles
FACTOR = 4                           # 30" source samples per 2' cell edge
SRC_NODATA = -99999.0


def lat_weights(src_row0, nrows, src_rows_total):
    """Area weight (cos latitude of the sample centre) for source rows, float64."""
    j = np.arange(src_row0, src_row0 + nrows, dtype=np.float64)
    lat = 90.0 - (j + 0.5) * 180.0 / src_rows_total
    return np.cos(np.radians(lat))


def round_half_up(x):
    """Deterministic rounding to nearest integer, halves toward +inf (not banker's)."""
    return np.floor(x + 0.5)


def aggregate_band(elev, land, lake, w, factor=FACTOR):
    """Aggregate a band of source samples into output cells.

    elev: float32 (rows, cols) heights in metres, NaN = no data. rows, cols multiples of `factor`.
    land: bool, sample centre inside the Natural Earth land polygon (lakes NOT yet cut out).
    lake: bool, sample centre inside a Natural Earth lake polygon (wins over land).
    w:    float64 (rows,) area weights per source row.
    Returns (heights int16 (rows/f, cols/f), water bool of the same shape).

    Rules (ADR 0001): classify by polygon containment, never by elevation sign. Land and
    water are aggregated separately. Output cell is land if land area >= water area (land
    wins ties), then holds the land-sample weighted mean, negative land kept. Otherwise it
    is water: ocean-majority water is sea level (0); lake-majority water keeps the lake
    surface mean. Samples with no data are excluded from means; if a class has no valid
    sample the cell is NODATA.
    """
    r, c = elev.shape
    if r % factor or c % factor:
        raise ValueError("band not a multiple of the aggregation factor")
    valid = ~np.isnan(elev)
    is_lake = lake
    is_land = land & ~lake
    is_ocean = ~land & ~lake
    W = np.broadcast_to(w[:, None], elev.shape)
    e0 = np.where(valid, elev, 0.0).astype(np.float64)

    def block(a):
        return a.reshape(r // factor, factor, c // factor, factor).sum(axis=(1, 3))

    area_land = block(W * is_land)
    area_lake = block(W * is_lake)
    area_ocean = block(W * is_ocean)
    wv_land = block(W * (is_land & valid))
    wv_lake = block(W * (is_lake & valid))
    s_land = block(W * e0 * (is_land & valid))
    s_lake = block(W * e0 * (is_lake & valid))

    area_water = area_lake + area_ocean
    cell_land = area_land >= area_water
    lake_major = (~cell_land) & (area_lake > area_ocean)

    with np.errstate(invalid="ignore", divide="ignore"):
        mean_land = s_land / wv_land
        mean_lake = s_lake / wv_lake
    h = np.zeros(cell_land.shape, dtype=np.float64)          # ocean = sea level
    h = np.where(cell_land, np.where(wv_land > 0, mean_land, NODATA), h)
    h = np.where(lake_major, np.where(wv_lake > 0, mean_lake, NODATA), h)
    h = np.where(h == NODATA, NODATA, np.clip(round_half_up(h), -32767, 32767))
    return h.astype(np.int16), ~cell_land


def pack_tile(h, water):
    """Tile bytes: int16 little-endian row-major heights, then water bits (1 = water),
    row-major, least-significant bit first."""
    h = np.ascontiguousarray(h, dtype="<i2")
    bits = np.packbits(water.reshape(-1).astype(np.uint8), bitorder="little")
    return h.tobytes() + bits.tobytes()


def unpack_tile(data, rows=TILE_ROWS, cols=TILE_COLS):
    n = rows * cols
    if len(data) != tile_size(rows, cols):
        raise ValueError("bad tile size %d" % len(data))
    h = np.frombuffer(data[: 2 * n], dtype="<i2").reshape(rows, cols)
    bits = np.frombuffer(data[2 * n:], dtype=np.uint8)
    water = np.unpackbits(bits, bitorder="little")[:n].reshape(rows, cols).astype(bool)
    return h, water


def tile_size(rows=TILE_ROWS, cols=TILE_COLS):
    return 2 * rows * cols + (rows * cols + 7) // 8


def tile_name(ty, tx):
    return "t%02d_%02d.rpt" % (ty, tx)


def split_tiles(h, water, tile_rows=TILE_ROWS, tile_cols=TILE_COLS):
    """Yield (ty, tx, bytes). Tiles partition the grid: no shared or duplicated border cells."""
    rows, cols = h.shape
    if rows % tile_rows or cols % tile_cols:
        raise ValueError("grid is not a whole number of tiles")
    for ty in range(rows // tile_rows):
        for tx in range(cols // tile_cols):
            ys, xs = slice(ty * tile_rows, (ty + 1) * tile_rows), slice(tx * tile_cols, (tx + 1) * tile_cols)
            yield ty, tx, pack_tile(h[ys, xs], water[ys, xs])


def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def sha256_file(path, chunk=1 << 20):
    d = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(chunk)
            if not b:
                return d.hexdigest()
            d.update(b)


def cell_index(lat, lon, rows=GRID_ROWS, cols=GRID_COLS):
    """(row, col) of the cell containing lat/lon. Longitude wraps (antimeridian); latitude
    clamps (poles). Row 0 is the northernmost row, col 0 starts at -180."""
    lon = (lon + 180.0) % 360.0
    col = min(int(lon / 360.0 * cols), cols - 1)
    row = int((90.0 - min(max(lat, -90.0), 90.0)) / 180.0 * rows)
    return min(row, rows - 1), col


class Reader:
    """Reads cells from a prepared bundle directory without loading the whole globe."""

    def __init__(self, directory, rows=GRID_ROWS, cols=GRID_COLS, tile_rows=TILE_ROWS, tile_cols=TILE_COLS):
        self.dir, self.rows, self.cols, self.tr, self.tc = directory, rows, cols, tile_rows, tile_cols
        self._cache = {}

    def tile(self, ty, tx):
        k = (ty, tx)
        if k not in self._cache:
            with open("%s/%s" % (self.dir, tile_name(ty, tx)), "rb") as f:
                self._cache[k] = unpack_tile(f.read(), self.tr, self.tc)
            if len(self._cache) > 64:
                self._cache.pop(next(iter(self._cache)))
        return self._cache[k]

    def cell(self, row, col):
        col %= self.cols
        row = min(max(row, 0), self.rows - 1)
        h, wtr = self.tile(row // self.tr, col // self.tc)
        return int(h[row % self.tr, col % self.tc]), bool(wtr[row % self.tr, col % self.tc])

    def region(self, row0, row1, col0, col1):
        """Heights and water for [row0,row1) x [col0,col1); columns may wrap."""
        out_h = np.empty((row1 - row0, col1 - col0), dtype=np.int16)
        out_w = np.empty(out_h.shape, dtype=bool)
        for r in range(row0, row1):
            rr = min(max(r, 0), self.rows - 1)
            c = col0
            while c < col1:
                cc = c % self.cols
                h, wtr = self.tile(rr // self.tr, cc // self.tc)
                x0 = cc % self.tc
                n = min(self.tc - x0, col1 - c)
                out_h[r - row0, c - col0:c - col0 + n] = h[rr % self.tr, x0:x0 + n]
                out_w[r - row0, c - col0:c - col0 + n] = wtr[rr % self.tr, x0:x0 + n]
                c += n
        return out_h, out_w


# ---- Natural Earth I land cover (4 arc-minute, 8-bit palette indices) -------------------
LC_COLS, LC_ROWS = 5400, 2700   # 4' cells, same registration as the heights (cell-centred, row 0 north)
LC_NONE = 0                     # index 0 = "no land cover" (ocean / blank in the source)
LC_FILE = "landcover-4arcmin.u8"
LC_WHITE = (255, 255, 255)


def reduce_landcover(rgb, factor=3, chunk_rows=10):
    """rgb uint8 (H, W, 3) -> (mean colour of non-blank source pixels float64 (H/f, W/f, 3),
    has_cover bool). A cell has cover unless a majority of its factor*factor source pixels
    are pure white (the source's blank/ocean colour). Coast cells keep the land colour
    instead of a white fringe. Processed in row chunks to bound memory."""
    h, w, _ = rgb.shape
    if h % factor or w % factor:
        raise ValueError("raster not a multiple of the reduction factor")
    mean = np.empty((h // factor, w // factor, 3))
    cover = np.empty((h // factor, w // factor), dtype=bool)
    for r0 in range(0, h // factor, chunk_rows):
        r1 = min(r0 + chunk_rows, h // factor)
        blk = rgb[r0 * factor:r1 * factor].reshape(r1 - r0, factor, w // factor, factor, 3).astype(np.int64)
        blank = (blk == 255).all(axis=4)
        keep = ~blank
        cnt = keep.sum(axis=(1, 3))
        s = (blk * keep[..., None]).sum(axis=(1, 3))
        mean[r0:r1] = s / np.maximum(cnt, 1)[..., None]
        cover[r0:r1] = blank.sum(axis=(1, 3)) * 2 < factor * factor
    return mean, cover


def median_cut_palette(colors, weights, n):
    """Deterministic weighted median cut. colors int (K,3) unique, weights (K,). Returns uint8
    (n,3), sorted by (r,g,b), padded by repeating the last entry if fewer than n colours."""
    order = np.lexsort((colors[:, 2], colors[:, 1], colors[:, 0]))
    colors, weights = colors[order].astype(np.int64), weights[order].astype(np.int64)
    boxes = [np.arange(len(colors))]
    while len(boxes) < n:
        best, score = -1, 0.0
        for i, b in enumerate(boxes):
            if len(b) < 2:
                continue
            c, w = colors[b], weights[b]
            m = (c * w[:, None]).sum(0) / w.sum()
            sc = float(((c - m) ** 2 * w[:, None]).sum())
            if sc > score:
                best, score = i, sc
        if best < 0:
            break
        b = boxes.pop(best)
        c = colors[b]
        axis = int(np.argmax(c.max(0) - c.min(0)))
        o = b[np.lexsort((np.arange(len(b)), c[:, axis]))]      # stable
        cw = np.cumsum(weights[o])
        cut = int(np.searchsorted(cw, cw[-1] / 2.0)) + 1
        cut = min(max(cut, 1), len(o) - 1)
        boxes += [o[:cut], o[cut:]]
    pal = []
    for b in boxes:
        w = weights[b]
        pal.append(np.floor((colors[b] * w[:, None]).sum(0) / w.sum() + 0.5).astype(np.int64))
    pal = np.array(sorted(map(tuple, pal)), dtype=np.int64)
    if len(pal) < n:
        pal = np.vstack([pal, np.repeat(pal[-1:], n - len(pal), axis=0)])
    return pal.astype(np.uint8)


def quantize(colors, palette, chunk=20_000):
    """Nearest palette index (ties -> lowest index) for float colours (N,3)."""
    out = np.empty(len(colors), dtype=np.int64)
    p = palette.astype(np.float64)
    for i in range(0, len(colors), chunk):
        c = colors[i:i + chunk].astype(np.float64)
        d = ((c[:, None, :] - p[None, :, :]) ** 2).sum(2)
        out[i:i + chunk] = np.argmin(d, axis=1)
    return out


def build_landcover(rgb, factor=3, palette_size=255, sample_step=1):
    """rgb (H,W,3) uint8 -> (indices uint8 (H/f, W/f) with 0 = none, palette uint8 (256,3)
    where entry 0 is the reserved 'no cover' slot (0,0,0) and entries 1..255 are used)."""
    mean, cover = reduce_landcover(rgb, factor)
    q = np.floor(mean + 0.5).astype(np.int64)
    flat = q[cover]
    key = (flat[:, 0] << 16) | (flat[:, 1] << 8) | flat[:, 2]
    uk, cnt = np.unique(key, return_counts=True)
    colors = np.stack([uk >> 16, (uk >> 8) & 255, uk & 255], 1)
    pal = median_cut_palette(colors, cnt, palette_size)
    idx = np.zeros(cover.shape, dtype=np.uint8)
    idx[cover] = (quantize(flat, pal) + 1).astype(np.uint8)
    full = np.vstack([np.zeros((1, 3), np.uint8), pal])
    return idx, full


def landcover_cell(idx, lat, lon):
    r, c = cell_index(lat, lon, idx.shape[0], idx.shape[1])
    return int(idx[r, c])
