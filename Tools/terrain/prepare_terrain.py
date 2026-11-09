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
    classification tolerance. Each record is rasterized on its own as outer rings minus its own
    holes (rings wound like a shapefile outer ring are filled, opposite winding are holes) and
    then merged, so one record's hole can never erase another record's polygon."""

    def __init__(self, shp_path, width, height):
        import shapefile
        self.w, self.h = width, height
        sx, sy = width / 360.0, height / 180.0
        self.records = []   # each: (ymin, ymax, xmin, xmax, [(xy, fill)])
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
                rings.append((xy, 1 if area > 0 else 0))
            if rings:
                xs = [p[0] for xy, _ in rings for p in xy]; ys = [p[1] for xy, _ in rings for p in xy]
                self.records.append((min(ys), max(ys), min(xs), max(xs), rings))

    def band(self, y0, n, ids=False):
        """Rows [y0, y0+n) (rows outside the globe are empty). bool array (n, width), or with
        ids=True an int32 array holding the 1-based record number (higher number wins overlaps)."""
        from PIL import Image, ImageDraw
        out = np.zeros((n, self.w), dtype=np.int32 if ids else bool)
        for rid, (ymin, ymax, xmin, xmax, rings) in enumerate(self.records, 1):
            ya, yb = max(int(np.floor(ymin)) - 1, y0), min(int(np.ceil(ymax)) + 2, y0 + n)
            xa, xb = max(int(np.floor(xmin)) - 1, 0), min(int(np.ceil(xmax)) + 2, self.w)
            if ya >= yb or xa >= xb:
                continue
            im = Image.new("L", (xb - xa, yb - ya), 0)
            d = ImageDraw.Draw(im)
            for xy, fill in rings:
                d.polygon([(x - xa, y - ya) for x, y in xy], fill=255 if fill else 0)
            m = np.asarray(im, dtype=bool)
            out[ya - y0:yb - y0, xa:xb][m] = rid if ids else True
        return out


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

    INLAND_SEAS = [("Caspian Sea", 42.0, 50.8)]   # ocean-classified body the polygons leave out of the lakes layer
    with tifffile.TiffFile(a.etopo) as tf:
        page = tf.pages[0]
        W, H = page.imagewidth, page.imagelength
        if (W, H) != (T.GRID_COLS * T.FACTOR, T.GRID_ROWS * T.FACTOR):
            sys.exit("unexpected source size %dx%d" % (W, H))
        th = page.tilelength
        nbands = (H + th - 1) // th
        land = Polygons(os.path.join(a.land, "ne_10m_land.shp"), W, H)
        lake = Polygons(os.path.join(a.lakes, "ne_10m_lakes.shp"), W, H)
        nlakes = len(lake.records)
        with open(a.etopo, "rb") as fh:
            def bands():
                """(y0, band, row above or None, row below or None) for every tile row."""
                cache = {}
                def get(i):
                    if i not in cache:
                        cache.pop(i - 3, None)
                        cache[i] = read_etopo_band(tf, page, fh, i, W)
                    return cache[i]
                for i in range(nbands):
                    cur = get(i)
                    yield i * th, cur, (get(i - 1)[-1] if i > 0 else None), (get(i + 1)[0] if i + 1 < nbands else None)

            def masks(y0, n):
                ids = lake.band(y0 - 1, n + 2, ids=True)
                lm = ids > 0
                landm = land.band(y0 - 1, n + 2)
                return ids, lm, landm & ~lm          # (lake ids, lake mask, land-only mask), padded by one row

            def padded(cur, above, below):
                nan = np.full((1, W), np.nan, dtype=np.float32)
                return np.vstack([nan if above is None else above[None, :], cur, nan if below is None else below[None, :]])

            print("pass 1: flat lake levels", flush=True)
            shore = {}                                  # lake id -> list of shore heights
            own_sum = np.zeros(nlakes + 1); own_cnt = np.zeros(nlakes + 1)
            for k, (y0, cur, above, below) in enumerate(bands()):
                n = cur.shape[0]
                ids, lm, lonly = masks(y0, n)
                ep, _ = T.clamp_land(padded(cur, above, below), lonly)
                lid, vals = T.ring_samples(ep, lonly, ids)
                if lid.size:
                    o = np.argsort(lid, kind="stable"); lid, vals = lid[o], vals[o]
                    cuts = np.flatnonzero(np.diff(lid)) + 1
                    for g, v in zip(np.split(lid, cuts), np.split(vals, cuts)):
                        shore.setdefault(int(g[0]), []).append(v)
                inner, own = ids[1:-1], cur
                ok = (inner > 0) & ~np.isnan(own)
                own_sum += np.bincount(inner[ok], weights=own[ok].astype(np.float64), minlength=nlakes + 1)
                own_cnt += np.bincount(inner[ok], minlength=nlakes + 1)
                print("  band %d/%d" % (k + 1, nbands), flush=True)
            levels, from_shore, from_own = {}, 0, 0
            for lid in range(1, nlakes + 1):
                if lid in shore:
                    levels[lid] = T.flat_level(np.concatenate(shore[lid])); from_shore += 1
                elif own_cnt[lid] > 0:
                    levels[lid] = int(np.floor(own_sum[lid] / own_cnt[lid] + 0.5)); from_own += 1
            print("lake levels: %d shore-based, %d fallback, %d without data" % (from_shore, from_own, nlakes - len(levels)), flush=True)

            print("pass 2: aggregate", flush=True)
            out_h = np.empty((T.GRID_ROWS, T.GRID_COLS), dtype=np.int16)
            out_w = np.empty((T.GRID_ROWS, T.GRID_COLS), dtype=bool)
            out_o = np.empty((T.GRID_ROWS, T.GRID_COLS), dtype=bool)
            clamped = 0
            for k, (y0, cur, above, below) in enumerate(bands()):
                n = cur.shape[0]
                ids, lm, lonly = masks(y0, n)
                ids_i, lm_i, lonly_i = ids[1:-1], lm[1:-1], lonly[1:-1]
                band, c = T.clamp_land(cur, lonly_i)
                clamped += c
                band = T.apply_lake_levels(band, ids_i, levels)
                w = T.lat_weights(y0, n, H)
                h, wt, oc = T.aggregate_band(band, lonly_i | lm_i, lm_i, w, return_ocean=True)
                sl = slice(y0 // T.FACTOR, (y0 + n) // T.FACTOR)
                out_h[sl], out_w[sl], out_o[sl] = h, wt, oc
                print("  band %d/%d" % (k + 1, nbands), flush=True)

    inland = []
    for name, lat, lon in INLAND_SEAS:
        r, c = T.cell_index(lat, lon)
        member, level = T.inland_sea(out_o, out_h, out_w, r, c)
        if member is None or level is None:
            sys.exit("inland sea %s not found" % name)
        out_h[member] = level
        inland.append({"name": name, "cells": int(member.sum()), "level_m": level})
        print("inland sea %s: %d cells at %d m" % (name, member.sum(), level))

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
        "lakes": {"mapped": nlakes, "levels_from_shore": from_shore, "levels_from_own_samples": from_own,
                  "without_level": nlakes - len(levels)},
        "inland_seas": inland,
        "land_floor_m": int(T.LAND_FLOOR), "land_samples_clamped": clamped,
        "rules": {"aggregation": "area-weighted (cos lat) mean of 4x4 30-arc-second samples, per class",
                  "rounding": "floor(x+0.5) to int16 metres", "classification": "Natural Earth polygon containment at sample centres",
                  "mixed_cells": "majority area; land wins ties", "ocean": "0 m, water bit set",
                  "inland_water": "every mapped lake is one flat level: median of the land samples within one source sample "
                                  "of its polygon (fallback: mean of its own samples); water bit set",
                  "inland_seas": "ocean-classified water bodies the polygons leave out of the lakes layer get one flat level "
                                 "(median of the land cells touching them); water bit set",
                  "land_floor": "land-classified source samples are clamped to %d m before averaging; classification is unchanged"
                                % int(T.LAND_FLOOR),
                  "negative_land": "kept above the land floor",
                  "antimeridian": "columns wrap (col 0 follows col 10799); no seam samples stored",
                  "poles": "rows clamp; no pole row exists (nearest centres +-89.98333 deg)"},
        "sources": src,
        "sizes": {"tiles": len(tiles), "installed_bytes": total, "installed_mib": round(total / 2**20, 3),
                  "cap_mib": 140, "elevation_only_mib": round(T.GRID_COLS * T.GRID_ROWS * 2 / 2**20, 3)},
        "tile_files": tiles,
    }
    with open(os.path.join(a.out, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
        f.write("\n")
    print("wrote %d tiles, %.3f MiB, nodata cells %d" % (len(tiles), total / 2**20, nd))
    if total > 140 * 2**20:
        sys.exit("over the 140 MiB cap")


if __name__ == "__main__":
    main()
