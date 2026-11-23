#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
mode=${1:---all}
case "$mode" in --all|--static|--core) ;; *) echo 'Usage: check.sh [--all|--static|--core]' >&2; exit 2;; esac
if [[ "$mode" != --core ]]; then
  node Tools/design/gen-tokens.mjs
  node Tools/design/gen-road-signs.mjs
  git -c safe.directory="$PWD" diff --exit-code -- App/Design/Tokens.generated.swift App/Design/RoadSigns.generated.swift App/Assets.xcassets
  test -z "$(git -c safe.directory="$PWD" ls-files --others --exclude-standard App/Assets.xcassets)"
  node --test Tools/design/gen-tokens.test.mjs Tools/ci/check-privacy-keys.test.mjs Tools/promo-video/render.test.mjs
  node Tools/design/check-app-literals.mjs
  node Tools/design/check-fonts.mjs
  node Tools/ci/check-privacy-keys.mjs
  python3 -m unittest discover -s Tools/automation -p 'test_*.py'
  python3 -m unittest discover -s Tools/appstore-preview -p 'test_*.py'
  python3 Tools/cloudkit/check_schema.py
fi
if [[ "$mode" != --static ]]; then
  # The server-wide swift wrapper serializes compilations. Two jobs bound memory.
  swift test --package-path RoadPrintCore --jobs "${SWIFT_JOBS:-2}"
fi
