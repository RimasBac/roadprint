#!/usr/bin/env bash
set -euo pipefail
profile=${1:-quick}
case "$profile" in quick|targeted|regression|tests|routine|full) ;; *) echo 'Unknown test profile' >&2; exit 2;; esac
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
  regression|tests) selection=(-skip-testing:RoadPrintUITests/TokensGalleryScreenshotTests);;
esac
# Build once. A persistent Mac retains the directories; CI uses the same entry point.
xcodebuild build-for-testing "${common[@]}" | tee build/compile.log | tail -n 60
# UI tests manipulate global simulator state. Keep them serial until sharding is proven.
xcodebuild test-without-building "${common[@]}" -parallel-testing-enabled NO \
  -resultBundlePath build/RoadPrint.xcresult "${selection[@]}" | tee build/xcodebuild.log | tail -n 80
