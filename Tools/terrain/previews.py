#!/usr/bin/env python3
"""Hillshaded relief previews from a prepared bundle, for the quality review (not shipped).
Usage: previews.py BUNDLE_DIR OUT_DIR [NE1_LR_LC.tif]
With the source land-cover tif it also writes brenner-landcover-4arcmin-vs-source.png:
left = bundled 4-arc-minute palette layer (bilinear, as core will look it up), right = the
source raster at native 1.33 arc-minutes (finer than any 2-arc-minute layer could be)."""
import os, sys
import numpy as np
from PIL import Image
import rpterrain as T

CROPS = {  # name: (lat_n, lat_s, lon_w, lon_e)
    "i80-sierra-to-wyoming": (44.0, 36.0, -124.0, -104.0),
    "brenner-alps": (48.5, 45.5, 9.0, 14.0),
    "nullarbor": (-29.0, -34.0, 124.0, 134.0),
}


def render(reader, lat_n, lat_s, lon_w, lon_e, scale=3, colour=None):
    r0, c0 = T.cell_index(lat_n, lon_w); r1, c1 = T.cell_index(lat_s, lon_e)
    h, w = reader.region(r0, r1 + 1, c0, c1 + 1)
    z = np.where(h == T.NODATA, 0, h).astype(np.float64)
    lat = np.radians(90 - (np.arange(r0, r1 + 1) + 0.5) / 30.0)
    dx = (np.cos(lat)[:, None] * 111_320 * 2 / 60.0) * np.ones_like(z)   # metres per cell east-west
    dy = 111_320 * 2 / 60.0
    exag = 5.0
    gy, gx = np.gradient(z * exag, dy)
    gx = gx / (dx / dy)
    az, el = np.radians(315), np.radians(45)
    nx, ny, nz = -gx, gy, np.ones_like(z)
    n = np.sqrt(nx**2 + ny**2 + nz**2)
    shade = (-nx * np.sin(az) * np.cos(el) + ny * np.cos(az) * np.cos(el) + nz * np.sin(el)) / n
    shade = np.clip(shade, 0, 1)
    zn = np.clip(z / 3500.0, 0, 1)
    base = np.stack([29 + 190 * zn, 32 + 150 * zn, 41 + 110 * zn], -1)   # dark land -> warm high ground
    if colour is not None:
        lat2 = 90 - (np.arange(r0, r1 + 1) + 0.5) / 30.0
        lon2 = -180 + (np.arange(c0, c1 + 1) + 0.5) / 30.0
        base = colour(lat2, lon2).astype(np.float64)
    img = base * (0.35 + 0.65 * shade[..., None])
    img[w] = np.array([20, 22, 28])                                      # water, as in tokens background
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    return im.resize((im.width * scale, im.height * scale), Image.NEAREST)


def lc_bilinear(idx, pal):
    """Bilinear lookup of palette colours on the 4' grid; no-cover neighbours are skipped."""
    rows, cols = idx.shape
    rgb = pal[idx].astype(np.float64); ok = (idx != 0).astype(np.float64)

    def f(lat, lon):
        y = (90 - lat) / 180 * rows - 0.5; x = ((lon + 180) % 360) / 360 * cols - 0.5
        y0 = np.floor(y).astype(int); x0 = np.floor(x).astype(int); fy = (y - y0)[:, None]; fx = (x - x0)[None, :]
        out = 0; wsum = 0
        for dy, wy in ((0, 1 - fy), (1, fy)):
            for dx, wx in ((0, 1 - fx), (1, fx)):
                yy = np.clip(y0 + dy, 0, rows - 1)[:, None]; xx = (x0 + dx)[None, :] % cols
                w = wy * wx * ok[yy, xx]
                out = out + w[..., None] * rgb[yy, xx]; wsum = wsum + w
        near = rgb[np.clip(np.round(y).astype(int), 0, rows - 1)[:, None], np.round(x).astype(int)[None, :] % cols]
        return np.where(wsum[..., None] > 0, out / np.maximum(wsum, 1e-9)[..., None], near)
    return f


def lc_source(tif):
    import tifffile
    a = tifffile.memmap(tif); H, W, _ = a.shape

    def f(lat, lon):
        y = np.clip(((90 - lat) / 180 * H).astype(int), 0, H - 1); x = (((lon + 180) % 360) / 360 * W).astype(int) % W
        return a[y[:, None], x[None, :]]
    return f


def main():
    bundle, out = sys.argv[1:3]
    os.makedirs(out, exist_ok=True)
    rd = T.Reader(bundle)
    for name, box in CROPS.items():
        im = render(rd, *box)
        im.save(os.path.join(out, name + ".png"))
        print(name, im.size)
    if len(sys.argv) > 3:
        import json
        m = json.load(open(os.path.join(bundle, "manifest.json")))["landcover"]
        idx = np.frombuffer(open(os.path.join(bundle, m["file"]), "rb").read(), dtype=np.uint8).reshape(m["rows"], m["cols"])
        pal = np.array(m["palette"]["rgb"], dtype=np.uint8)
        a = render(rd, *CROPS["brenner-alps"], colour=lc_bilinear(idx, pal))
        b = render(rd, *CROPS["brenner-alps"], colour=lc_source(sys.argv[3]))
        both = Image.new("RGB", (a.width + b.width + 8, a.height), (255, 255, 255))
        both.paste(a, (0, 0)); both.paste(b, (a.width + 8, 0))
        both.save(os.path.join(out, "brenner-landcover-4arcmin-vs-source.png"))
        a.save(os.path.join(out, "brenner-landcover-4arcmin.png")); b.save(os.path.join(out, "brenner-landcover-source.png"))
        print("comparison", both.size)


if __name__ == "__main__":
    main()
