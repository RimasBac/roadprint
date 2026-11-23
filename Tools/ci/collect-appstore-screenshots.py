"""Collect the named App Store screenshots from an xcresult attachment export."""
import json
import shutil
import struct
import sys
from pathlib import Path


NAMES = ('01-trip-summary', '02-night-highway', '03-my-map', '04-drive', '05-trip-card-video')
# Extra captures for the promo video (Tools/promo-video), never uploaded to the store.
PROMO_NAMES = ('promo-my-map',)


def collect(export, output, names=NAMES):
    manifest = json.loads((export / 'manifest.json').read_text())
    attachments = [item for test in manifest for item in test['attachments']]
    screenshots = []
    for name in names:
        matches = [
            export / item['exportedFileName']
            for item in attachments
            if item['suggestedHumanReadableName'].startswith(name)
            and item['exportedFileName'].endswith('.png')
        ]
        if len(matches) != 1:
            raise SystemExit(f'{name}: expected one PNG attachment, found {len(matches)}')
        source = matches[0]
        with source.open('rb') as png:
            header = png.read(26)
        if len(header) != 26 or header[:16] != b'\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR':
            raise SystemExit(f'{name}: invalid PNG header')
        width, height, depth, color_type = struct.unpack('>IIBB', header[16:])
        if (width, height, depth, color_type) != (1320, 2868, 8, 2):
            raise SystemExit(f'{name}: expected 1320×2868 RGB PNG, got {width}×{height}, '
                             f'bit depth {depth}, PNG color type {color_type}')
        screenshots.append((source, output / f'{name}.png'))

    output.mkdir(parents=True, exist_ok=True)
    for source, target in screenshots:
        shutil.copyfile(source, target)
        print(target)


if __name__ == '__main__':
    # collect-appstore-screenshots.py EXPORT STORE_DIR [PROMO_DIR]: the five store PNGs, and with
    # PROMO_DIR the same five plus the promo-only captures, for Tools/promo-video.
    collect(Path(sys.argv[1]), Path(sys.argv[2]))
    if len(sys.argv) > 3:
        collect(Path(sys.argv[1]), Path(sys.argv[3]), NAMES + PROMO_NAMES)
