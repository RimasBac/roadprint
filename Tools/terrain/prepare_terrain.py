#!/usr/bin/env python3
"""Build the RoadPrint terrain bundle (RPTERR v1) from pinned ETOPO 2022 + Natural Earth.

Usage: prepare_terrain.py --etopo FILE.tif --land DIR --lakes DIR --out DIR
Run with the interpreter from a venv built from requirements.txt. Linux only; never in the app.
Inputs are verified against sources/sources.json checksums before any output is written.
Deterministic: same inputs -> byte-identical tiles and manifest (no timestamps).
"""
import argparse, json, os, sys
import numpy as np
import rpterrain as T

HERE = os.path.dirname(os.path.abspath(__file__))


def load_sources():
    with open(os.path.join(HERE, "sources", "sources.json")) as f:
        return json.load(f)


class Polygons:
    """Natural Earth polygons, rasterized one band of rows at a time (a full-globe raster at
    30 arc-seconds would need ~1 GB per layer).

    Containment is tested at source sample centres: sample (i, j) has centre
    lon=-180+(i+.5)/120, lat=90-(j+.5)/120, and polygon coordinates are mapped so pixel
    centres coincide with sample centres. Pillow's fill is inclusive of edges, so a sample
    within ~half a sample (~460 m) of a boundary may fall either side: the documented
    classification tolerance. Within a record, rings wound like the first are filled and
    the opposite winding are holes."""

    def __init__(self, shp_path, width, height):
        import shapefile
        self.w, self.h = width, height
        sx, sy = width / 360.0, height / 180.0
        self.records = []   # each: list of (ymin, ymax, xy, fill)
        for shp in shapefile.Reader(shp_path).iterShapes():
            pts = shp.points
            parts = list(shp.parts) + [len(pts)]
            rings = []
            for k in range(len(parts) - 1):
                xy = [((x + 180.0) * sx - 0.5, (90.0 - y) * sy - 0.5) for x, y in pts[parts[k]:parts[k + 1]]]
                if len(xy) < 3:
                    continue
                area = sum(xy[i][0] * xy[(i + 1) % len(xy)][1] - xy[(i + 1) % len(xy)][0] * xy[i][1] for i in range(len(xy)))
                # shapefile outer rings are clockwise in lon/lat => positive area in pixel space
                rings.append((min(p[1] for p in xy), max(p[1] for p in xy), xy, 1 if area > 0 else 0))
            self.records.append(rings)

    def band(self, y0, n):
        """bool array (n, width) for source rows [y0, y0+n)."""
        from PIL import Image, ImageDraw
        im = Image.new("L", (self.w, n), 0)
        d = ImageDraw.Draw(im)
        for rings in self.records:
            for ymin, ymax, xy, fill in rings:
                if ymax < y0 - 1 or ymin > y0 + n + 1:
                    continue
                d.polygon([(x, y - y0) for x, y in xy], fill=fill)
        return np.asarray(im, dtype=bool)


def read_etopo_band(tif, page, fh, ty, shape_cols):
    """Decode one row of 256x256 tiles (256 source rows) into float32 with NaN no-data."""
    tw, th = page.tilewidth, page.tilelength
    ntx = (page.imagewidth + tw - 1) // tw
    rows = min(th, page.imagelength - ty * th)
    band = np.empty((rows, page.imagewidth), dtype=np.float32)
    for tx in range(ntx):
        idx = ty * ntx + tx
        fh.seek(page.dataoffsets[idx])
        data = fh.read(page.databytecounts[idx])
        seg, _, _ = page.decode(data, idx)
        seg = np.asarray(seg).reshape(seg.shape[-3:-1] if seg.ndim > 2 else seg.shape)
        h, w = seg.shape
        h, w = min(h, rows), min(w, page.imagewidth - tx * tw)
        band[:h, tx * tw:tx * tw + w] = seg[:h, :w]
    band[band == T.SRC_NODATA] = np.nan
    return band


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--etopo", required=True)
    ap.add_argument("--land", required=True, help="directory with ne_10m_land.shp")
    ap.add_argument("--lakes", required=True, help="directory with ne_10m_lakes.shp")
    ap.add_argument("--out", required=True)
    ap.add_argument("--skip-checksums", action="store_true", help="development only")
    a = ap.parse_args()
    import tifffile
    src = load_sources()
    if not a.skip_checksums:
        for key, path in (("etopo", a.etopo),):
            got = T.sha256_file(path)
            if got != src[key]["sha256"]:
                sys.exit("checksum mismatch for %s: %s" % (key, got))
        for key, d in (("land", a.land), ("lakes", a.lakes)):
            for ext, want in src[key]["files_sha256"].items():
                got = T.sha256_file(os.path.join(d, "ne_10m_%s.%s" % (key, ext)))
                if got != want:
                    sys.exit("checksum mismatch for %s.%s: %s" % (key, ext, got))
    os.makedirs(a.out, exist_ok=True)

    with tifffile.TiffFile(a.etopo) as tf:
        page = tf.pages[0]
        W, H = page.imagewidth, page.imagelength
        if (W, H) != (T.GRID_COLS * T.FACTOR, T.GRID_ROWS * T.FACTOR):
            sys.exit("unexpected source size %dx%d" % (W, H))
        print("rasterizing masks", flush=True)
        land = Polygons(os.path.join(a.land, "ne_10m_land.shp"), W, H)
        lake = Polygons(os.path.join(a.lakes, "ne_10m_lakes.shp"), W, H)
        out_h = np.empty((T.GRID_ROWS, T.GRID_COLS), dtype=np.int16)
        out_w = np.empty((T.GRID_ROWS, T.GRID_COLS), dtype=bool)
        th = page.tilelength
        with open(a.etopo, "rb") as fh:
            for ty in range((H + th - 1) // th):
                y0 = ty * th
                band = read_etopo_band(tf, page, fh, ty, W)
                n = band.shape[0]
                lm, km = land.band(y0, n), lake.band(y0, n)
                w = T.lat_weights(y0, n, H)
                h, wt = T.aggregate_band(band, lm, km, w)
                out_h[y0 // T.FACTOR:(y0 + n) // T.FACTOR] = h
                out_w[y0 // T.FACTOR:(y0 + n) // T.FACTOR] = wt
                print("band %d/%d" % (ty + 1, (H + th - 1) // th), flush=True)

    tiles, total = [], 0
    for ty, tx, data in T.split_tiles(out_h, out_w):
        name = T.tile_name(ty, tx)
        with open(os.path.join(a.out, name), "wb") as f:
            f.write(data)
        tiles.append({"file": name, "bytes": len(data), "sha256": T.sha256_bytes(data)})
        total += len(data)
    nd = int((out_h == T.NODATA).sum())
    manifest = {
        "format": T.FORMAT, "version": T.VERSION,
        "grid": {"cols": T.GRID_COLS, "rows": T.GRID_ROWS, "cell_arcmin": 2, "registration": "cell-centre",
                 "lon_min": -180.0, "lat_max": 90.0, "row0": "north", "crs": "WGS84 (EPSG:4326)",
                 "vertical_datum": "EGM2008 (heights above geoid, metres)"},
        "tiles": {"rows": T.TILE_ROWS, "cols": T.TILE_COLS, "count_x": T.GRID_COLS // T.TILE_COLS,
                  "count_y": T.GRID_ROWS // T.TILE_ROWS, "name": "t{ty:02d}_{tx:02d}.rpt",
                  "bytes_each": T.tile_size(), "layout": "int16 LE row-major heights, then water bitmask "
                  "(row-major, LSB first, 1 = water); no header, no duplicated border cells"},
        "nodata_int16": T.NODATA, "nodata_cells": nd,
        "rules": {"aggregation": "area-weighted (cos lat) mean of 4x4 30-arc-second samples, per class",
                  "rounding": "floor(x+0.5) to int16 metres", "classification": "Natural Earth polygon containment at sample centres",
                  "mixed_cells": "majority area; land wins ties", "ocean": "0 m, water bit set",
                  "inland_water": "lake-surface weighted mean, water bit set", "negative_land": "kept",
                  "antimeridian": "columns wrap (col 0 follows col 10799); no seam samples stored",
                  "poles": "rows clamp; no pole row exists (nearest centres +-89.98333 deg)"},
        "sources": src,
        "sizes": {"tiles": len(tiles), "installed_bytes": total, "installed_mib": round(total / 2**20, 3),
                  "cap_mib": 120, "elevation_only_mib": round(T.GRID_COLS * T.GRID_ROWS * 2 / 2**20, 3)},
        "tile_files": tiles,
    }
    with open(os.path.join(a.out, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
        f.write("\n")
    print("wrote %d tiles, %.3f MiB, nodata cells %d" % (len(tiles), total / 2**20, nd))
    if total > 120 * 2**20:
        sys.exit("over the 120 MiB cap")


if __name__ == "__main__":
    main()
