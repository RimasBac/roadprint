#!/usr/bin/env python3
"""Bundled land-cover colour for the Terrain card (ADR 0006 point 5).

Natural Earth I land cover (NE1_LR_LC, public domain), already resampled to 2 arc-minutes by
fetch_landcover.py, box-averaged to a 4 arc-minute global equirectangular grid (5400 x 2700,
row 0 = 90 N, column 0 = 180 W) and quantised to a 256-colour palette. Writes
App/Resources/Terrain/landcover-4min.png (about 3 MB). The core grades this colour for the dark card
(terrain.landCover tokens) and reads near-white as water.

Usage: python3 fetch_landcover.py && python3 build_landcover_bundle.py   (needs pillow)
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, ".cache", "ne", "ne1_2min.png")
OUT = os.path.join(HERE, "..", "..", "App", "Resources", "Terrain", "landcover-4min.png")

Image.MAX_IMAGE_PIXELS = None
im = Image.open(SRC).convert("RGB").resize((5400, 2700), Image.BOX)
im.quantize(colors=256, method=Image.Quantize.MEDIANCUT).save(OUT, optimize=True)
print(os.path.normpath(OUT), os.path.getsize(OUT), "bytes")
