#!/usr/bin/env bash
set -euo pipefail
profile=${1:-quick}
case "$profile" in quick|targeted|regression|tests|routine|full|appstore|apppreview) ;; *) echo 'Unknown test profile' >&2; exit 2;; esac
mkdir -p build
common=(-project RoadPrint.xcodeproj -scheme RoadPrint -destination "id=$SIM_UDID"
  -derivedDataPath "${RP_DERIVED_DATA:-DerivedData}" -clonedSourcePackagesDirPath "${RP_SOURCE_PACKAGES:-SourcePackages}"
  COMPILER_INDEX_STORE_ENABLE=NO CODE_SIGNING_ALLOWED=NO)
selection=()
case "$profile" in
  quick) selection=(-only-testing:RoadPrintTests -only-testing:RoadPrintUITests/LaunchScreenshotTests -only-testing:RoadPrintUITests/YourDataTests);;
  targeted)
    [[ "${TEST_FILTER:-}" =~ ^(RoadPrintTests|RoadPrintUITests)/[A-Za-z0-9_]+(/[A-Za-z0-9_]+)?$ ]] || { echo 'targeted needs Target/Class[/test]'; exit 2; }
    selection=("-only-testing:$TEST_FILTER");;
  regression|tests) selection=(-skip-testing:RoadPrintUITests/TokensGalleryScreenshotTests -skip-testing:RoadPrintUITests/AppStoreScreenshotTests);;
  routine|full) selection=(-skip-testing:RoadPrintUITests/AppStoreScreenshotTests);;
  appstore) selection=(-only-testing:RoadPrintUITests/AppStoreScreenshotTests);;
  apppreview) selection=(-only-testing:RoadPrintUITests/AppPreviewTests);;
esac
# Build once. A persistent Mac retains the directories; CI uses the same entry point.
xcodebuild build-for-testing "${common[@]}" | tee build/compile.log | tail -n 60
# UI tests manipulate global simulator state. Keep them serial until sharding is proven.
recorder=
if [[ "$profile" == apppreview ]]; then
  # Record the whole test run; make-app-preview.py keeps only the test's marked blocks.
  xcrun simctl io "$SIM_UDID" recordVideo --codec=h264 --force build/preview-raw.mov > build/record.log 2>&1 &
  recorder=$!
  for _ in $(seq 100); do grep -q 'Recording started' build/record.log && break; sleep 0.1; done
  python3 -c 'import time; print(f"{time.time():.3f}")' > build/record-start.txt
fi
status=0
xcodebuild test-without-building "${common[@]}" -parallel-testing-enabled NO \
  -resultBundlePath build/RoadPrint.xcresult ${selection[@]+"${selection[@]}"} | tee build/xcodebuild.log | tail -n 80 || status=$?
if [[ -n "$recorder" ]]; then
  kill -INT "$recorder"
  wait "$recorder" || true
fi
exit "$status"
