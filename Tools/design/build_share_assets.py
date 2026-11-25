#!/usr/bin/env python3
"""Share-sheet assets (ROA-128): the Print card's two sample backdrops and the style thumbnails.

Backdrops (App/Resources/ShareBackdrops/, 1080 x 1920 JPEG), from Tools/design/fixtures/photos (see its
README for source and licence; both are free to redistribute):
  night-sky.jpg   Arches National Park, public domain: the night preview crop (x from 1000 px, 1920 high)
  bright-sky.jpg  Trixia Lao, CC0: centred crop of the 1280 x 1920 frame
Thumbnails (App/Resources/ShareStyles/, 180 x 320 JPEG: 60 x 107 pt at 3x) and the Terrain sample
(540 x 960) are the app's own renders of the I-80 fixture (CardDebugView), passed in as 1080 x 1920 PNGs:
  --cards DIR with nightHighway.png, roadAtlas.png, terrain.png (CI evidence of MenuEvidenceTests),
  and Design/cards/print/previews/i80-night.png for Print.

Usage: python3 build_share_assets.py --cards DIR   (needs pillow)
"""
import argparse, os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
PHOTOS = os.path.join(HERE, "fixtures", "photos")
BACK = os.path.join(ROOT, "App", "Resources", "ShareBackdrops")
STYLES = os.path.join(ROOT, "App", "Resources", "ShareStyles")

def cover(im, w, h, left=None):
    k = max(w / im.width, h / im.height)
    im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    x = (im.width - w) // 2 if left is None else min(round(left * k), im.width - w)
    y = (im.height - h) // 2
    return im.crop((x, y, x + w, y + h))

def save(im, path, quality):
    im.convert("RGB").save(path, "JPEG", quality=quality, optimize=True, progressive=True)
    print(os.path.relpath(path, ROOT), os.path.getsize(path), "bytes")

ap = argparse.ArgumentParser()
ap.add_argument("--cards", required=True)
args = ap.parse_args()
os.makedirs(BACK, exist_ok=True)
os.makedirs(STYLES, exist_ok=True)

save(cover(Image.open(os.path.join(PHOTOS, "night-moab-pd.jpg")), 1080, 1920, left=1000), os.path.join(BACK, "night-sky.jpg"), 84)
save(cover(Image.open(os.path.join(PHOTOS, "bright-sky-cc0.jpg")), 1080, 1920), os.path.join(BACK, "bright-sky.jpg"), 84)

cards = {
    "nightHighway": os.path.join(args.cards, "nightHighway.png"),
    "roadAtlas": os.path.join(args.cards, "roadAtlas.png"),
    "print": os.path.join(ROOT, "Design", "cards", "print", "previews", "i80-night.png"),
    "terrain": os.path.join(args.cards, "terrain.png"),
}
for name, path in cards.items():
    save(Image.open(path).convert("RGB").resize((180, 320), Image.LANCZOS), os.path.join(STYLES, f"{name}.jpg"), 86)
save(Image.open(cards["terrain"]).convert("RGB").resize((540, 960), Image.LANCZOS), os.path.join(STYLES, "terrain-sample.jpg"), 84)
