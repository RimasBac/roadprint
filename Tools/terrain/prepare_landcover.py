#!/usr/bin/env python3
"""Add the Natural Earth I land-cover layer (ADR 0001 Amendment 1) to a terrain bundle.
Usage: prepare_landcover.py --tif NE1_LR_LC.tif --out BUNDLE_DIR [--skip-checksums]
Run after prepare_terrain.py: writes landcover-4arcmin.u8 and updates manifest.json
(palette, checksums, sizes). Deterministic."""
import argparse, json, os, sys
import numpy as np
import rpterrain as T
HERE = os.path.dirname(os.path.abspath(__file__))
CAP = 140 * 2**20


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tif", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--skip-checksums", action="store_true")
    a = ap.parse_args()
    import tifffile
    src = json.load(open(os.path.join(HERE, "sources", "sources.json")))["landcover"]
    if not a.skip_checksums and T.sha256_file(a.tif) != src["tif_sha256"]:
        sys.exit("checksum mismatch for land-cover tif")
    rgb = tifffile.memmap(a.tif)   # uncompressed: read lazily, bounded memory
    if rgb.shape != (T.LC_ROWS * 3, T.LC_COLS * 3, 3):
        sys.exit("unexpected land-cover raster shape %s" % (rgb.shape,))
    idx, pal = T.build_landcover(rgb)
    data = idx.astype(np.uint8).tobytes()
    open(os.path.join(a.out, T.LC_FILE), "wb").write(data)
    mp = os.path.join(a.out, "manifest.json")
    m = json.load(open(mp))
    m["landcover"] = {
        "file": T.LC_FILE, "bytes": len(data), "sha256": T.sha256_bytes(data),
        "cols": T.LC_COLS, "rows": T.LC_ROWS, "cell_arcmin": 4, "registration": "cell-centre",
        "layout": "uint8 palette index per cell, row-major, row 0 north, col 0 at lon -180; no header",
        "none_index": T.LC_NONE,
        "reduction": "3x3 source pixels per cell; a cell has no cover if a majority are pure white; otherwise "
                     "mean of its non-white pixels, then nearest palette entry",
        "palette": {"size": 256, "method": "deterministic weighted median cut of the cell colours into 255 entries, "
                    "sorted by (r,g,b); index 0 reserved (placeholder 0,0,0)",
                    "rgb": [list(map(int, c)) for c in pal]},
    }
    tiles = sum(t["bytes"] for t in m["tile_files"])
    manifest_bytes = 0
    m["sizes"].update({"landcover_bytes": len(data), "tiles_bytes": tiles, "cap_mib": 140,
                       "mask_mib_included_in_tiles": round(T.GRID_COLS * T.GRID_ROWS / 8 / 2**20, 3)})
    for _ in range(3):   # manifest size is part of the installed total; converge
        m["sizes"]["installed_bytes"] = tiles + len(data) + manifest_bytes
        m["sizes"]["installed_mib"] = round(m["sizes"]["installed_bytes"] / 2**20, 3)
        text = json.dumps(m, indent=1, sort_keys=True) + "\n"
        manifest_bytes = len(text.encode())
    open(mp, "w").write(text)
    print("land cover %d bytes; installed total %.3f MiB (cap 140)" % (len(data), m["sizes"]["installed_bytes"] / 2**20))
    if m["sizes"]["installed_bytes"] > CAP:
        sys.exit("over the 140 MiB cap")


if __name__ == "__main__":
    main()
