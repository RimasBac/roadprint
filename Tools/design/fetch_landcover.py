#!/usr/bin/env python3
"""Fetch Natural Earth I land cover (NE1_LR_LC, public domain) and resample it to the ADR 0001 2' grid.
Writes .cache/ne/ne1_2min.png (10800x5400). Design-preview tool only; ~75 MB download."""
import os, urllib.request, zipfile
import numpy as np
from PIL import Image

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.cache', 'ne')
os.makedirs(D, exist_ok=True)
z = os.path.join(D, 'NE1_LR_LC.zip')
if not os.path.exists(z):
    urllib.request.urlretrieve('https://naturalearth.s3.amazonaws.com/10m_raster/NE1_LR_LC.zip', z)
tif = zipfile.ZipFile(z).extract('NE1_LR_LC.tif', D)
im = Image.open(tif)
w, h = im.size
off = im.tile[0].offset            # uncompressed contiguous RGB strips: memory-map, resample in bands
a = np.memmap(tif, dtype=np.uint8, mode='r', offset=off, shape=(h, w, 3))
out = Image.new('RGB', (10800, 5400))
band = h // 27
for r in range(0, h, band):
    out.paste(Image.fromarray(np.array(a[r:r + band])).resize((10800, band * 5400 // h), Image.BOX), (0, r * 5400 // h))
out.save(os.path.join(D, 'ne1_2min.png'))
os.remove(tif)
print('ne1_2min.png 10800x5400')
