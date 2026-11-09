#!/usr/bin/env bash
# Download the pinned terrain bundle (GitHub release asset), verify its sha256, unpack it into
# App/Resources/Terrain/ (git-ignored). Needs `gh` (authenticated for the private repo), `jq`, `unzip`.
# Usage: Tools/terrain/fetch_bundle.sh [DEST]
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
lock="$root/Tools/terrain/bundle.lock.json"
dest="${1:-$root/App/Resources/Terrain}"
tag=$(jq -r .tag "$lock"); asset=$(jq -r .asset "$lock")
size=$(jq -r .bytes "$lock"); want=$(jq -r .sha256 "$lock"); repo=$(jq -r .repo "$lock")
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
gh release download "$tag" --repo "$repo" --pattern "$asset" --dir "$tmp"
got=$(sha256sum "$tmp/$asset" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$tmp/$asset" | cut -d' ' -f1)
[ "$(wc -c < "$tmp/$asset" | tr -d ' ')" = "$size" ] || { echo "size mismatch for $asset" >&2; exit 1; }
[ "$got" = "$want" ] || { echo "sha256 mismatch for $asset: $got" >&2; exit 1; }
rm -rf "$dest"; mkdir -p "$dest"
unzip -q "$tmp/$asset" -d "$dest"
echo "terrain bundle $tag unpacked into $dest"
