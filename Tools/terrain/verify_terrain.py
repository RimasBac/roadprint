#!/usr/bin/env python3
"""Verify a prepared terrain bundle against its manifest and the size budget; print a size report.
Usage: verify_terrain.py BUNDLE_DIR [--compressed]   (exit code 1 on any failure)"""
import argparse, json, os, sys, zipfile, tempfile
import numpy as np
import rpterrain as T

CAP = 140 * 2**20


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("dir"); ap.add_argument("--compressed", action="store_true")
    a = ap.parse_args()
    m = json.load(open(os.path.join(a.dir, "manifest.json")))
    bad = []
    if (m["format"], m["version"]) != (T.FORMAT, T.VERSION):
        bad.append("format/version")
    files = sorted(f for f in os.listdir(a.dir) if f.endswith(".rpt"))
    if files != sorted(t["file"] for t in m["tile_files"]):
        bad.append("tile file list differs from manifest")
    nx, ny = m["tiles"]["count_x"], m["tiles"]["count_y"]
    if len(files) != nx * ny:
        bad.append("expected %d tiles, found %d" % (nx * ny, len(files)))
    total = nodata = water = 0
    lo, hi = 32767, -32768
    for t in m["tile_files"]:
        p = os.path.join(a.dir, t["file"]); n = os.path.getsize(p)
        if n != t["bytes"] or n != T.tile_size():
            bad.append("size " + t["file"])
        if T.sha256_file(p) != t["sha256"]:
            bad.append("sha256 " + t["file"])
        h, w = T.unpack_tile(open(p, "rb").read())
        nodata += int((h == T.NODATA).sum()); water += int(w.sum())
        v = h[h != T.NODATA]
        if v.size:
            lo, hi = min(lo, int(v.min())), max(hi, int(v.max()))
        total += n
    lc = m.get("landcover")
    if lc is None:
        bad.append("manifest has no landcover section")
    else:
        p = os.path.join(a.dir, lc["file"])
        data = open(p, "rb").read()
        if len(data) != lc["bytes"] or len(data) != T.LC_COLS * T.LC_ROWS:
            bad.append("landcover size")
        if T.sha256_bytes(data) != lc["sha256"]:
            bad.append("landcover sha256")
        pal = lc["palette"]["rgb"]
        used = np.unique(np.frombuffer(data, dtype=np.uint8))
        if len(pal) != 256 or lc["none_index"] != T.LC_NONE:
            bad.append("palette shape / none index")
        if used.max() >= len(pal):
            bad.append("index outside palette")
        print("land cover: %d bytes, %d palette indices used, no-cover cells %.1f%%" % (len(data), len(used), 100 * float((np.frombuffer(data, dtype=np.uint8) == 0).mean())))
        total += len(data)
    manifest_bytes = os.path.getsize(os.path.join(a.dir, "manifest.json"))
    total += manifest_bytes
    if total != m["sizes"]["installed_bytes"]:
        bad.append("installed_bytes %d differs from files on disk %d" % (m["sizes"]["installed_bytes"], total))
    if total > CAP:
        bad.append("over the 120 MiB cap")
    cells = T.GRID_COLS * T.GRID_ROWS
    print("tiles: %d  installed: %d bytes = %.3f MiB (cap 140, margin %.3f MiB)" % (len(files), total, total / 2**20, (CAP - total) / 2**20))
    print("elevation-only base grid: %.3f MiB" % (cells * 2 / 2**20))
    print("water cells: %.2f%%  no-data cells: %d  height range: %d..%d m" % (100 * water / cells, nodata, lo, hi))
    if a.compressed:
        with tempfile.TemporaryDirectory() as d:
            z = os.path.join(d, "t.zip")
            with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
                for f in files + [T.LC_FILE, "manifest.json"]:
                    zf.write(os.path.join(a.dir, f), f)
            print("measured deflate-9 zip of the whole bundle: %d bytes = %.3f MiB" % (os.path.getsize(z), os.path.getsize(z) / 2**20))
    if bad:
        print("FAIL:", *bad, sep="\n  "); sys.exit(1)
    print("OK")


if __name__ == "__main__":
    main()
