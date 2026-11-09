#!/usr/bin/env python3
"""Deterministic release archive of a verified terrain bundle.
Usage: make_release_zip.py BUNDLE_DIR OUT.zip
Sorted entries, fixed timestamps (1980-01-01), fixed permissions, deflate level 9: the same
bundle always gives a byte-identical zip. Prints size and sha256 for bundle.lock.json."""
import os, sys, zipfile
import rpterrain as T


def main():
    src, out = sys.argv[1:3]
    names = sorted(f for f in os.listdir(src) if f.endswith(".rpt")) + [T.LC_FILE, "manifest.json"]
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for n in sorted(names):
            zi = zipfile.ZipInfo(n, date_time=(1980, 1, 1, 0, 0, 0))
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = 0o644 << 16
            zi.create_system = 3
            with open(os.path.join(src, n), "rb") as f:
                z.writestr(zi, f.read(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    print(os.path.getsize(out), T.sha256_file(out))


if __name__ == "__main__":
    main()
