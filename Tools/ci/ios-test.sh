#!/usr/bin/env bash
set -euo pipefail
profile=${1:-quick}
shard=${SHARD:-}
case "$profile" in build|quick|targeted|regression|tests|routine|full|appstore) ;; *) echo 'Unknown test profile' >&2; exit 2;; esac
if [[ -n "$shard" && "$profile" != regression && "$profile" != tests ]]; then
  echo 'SHARD applies only to regression and tests' >&2; exit 2
fi
mkdir -p build
common=(-project RoadPrint.xcodeproj -scheme RoadPrint -destination "id=$SIM_UDID"
  -derivedDataPath "${RP_DERIVED_DATA:-DerivedData}" -clonedSourcePackagesDirPath "${RP_SOURCE_PACKAGES:-SourcePackages}"
  COMPILER_INDEX_STORE_ENABLE=NO CODE_SIGNING_ALLOWED=NO)

# Regression shards, balanced from the per-test timings of run 45598799410 (~470 s each).
# Shards 1 and 2 name their tests; shard 3 runs everything else, so a new test lands
# there automatically. Rebalance when the Timing summary drifts.
shard_tests() {
  case "$1" in
    1) printf '%s\n' \
         RoadPrintUITests/MenuEvidenceTests/testShareCardFixtures \
         RoadPrintUITests/MenuEvidenceTests/testMyMapFromFiveToFiveHundredTrips \
         RoadPrintUITests/MenuEvidenceTests/testTabsYouTripDetailAndAllTrips;;
    2) printf '%s\n' \
         RoadPrintUITests/ImportExportTests \
         RoadPrintUITests/ProTests \
         RoadPrintUITests/DeleteAllDataTests \
         RoadPrintUITests/SyncBannerTests;;
  esac
}

selection=()
case "$profile" in
  build) ;;
  quick) selection=(-only-testing:RoadPrintTests -only-testing:RoadPrintUITests/LaunchScreenshotTests -only-testing:RoadPrintUITests/YourDataTests);;
  targeted)
    [[ "${TEST_FILTER:-}" =~ ^(RoadPrintTests|RoadPrintUITests)/[A-Za-z0-9_]+(/[A-Za-z0-9_]+)?$ ]] || { echo 'targeted needs Target/Class[/test]'; exit 2; }
    selection=("-only-testing:$TEST_FILTER");;
  regression|tests)
    case "$shard" in
      '') selection=(-skip-testing:RoadPrintUITests/TokensGalleryScreenshotTests -skip-testing:RoadPrintUITests/AppStoreScreenshotTests);;
      1|2) while read -r id; do selection+=("-only-testing:$id"); done < <(shard_tests "$shard");;
      3) selection=(-skip-testing:RoadPrintUITests/TokensGalleryScreenshotTests -skip-testing:RoadPrintUITests/AppStoreScreenshotTests)
         while read -r id; do selection+=("-skip-testing:$id"); done < <(shard_tests 1; shard_tests 2);;
      *) echo 'SHARD must be empty, 1, 2 or 3' >&2; exit 2;;
    esac;;
  routine|full) selection=(-skip-testing:RoadPrintUITests/AppStoreScreenshotTests);;
  appstore) selection=(-only-testing:RoadPrintUITests/AppStoreScreenshotTests);;
esac
# Build once. A persistent Mac retains the directories; CI uses the same entry point.
xcodebuild build-for-testing "${common[@]}" | tee build/compile.log | tail -n 60
if [[ "$profile" == build ]]; then exit 0; fi
# UI tests manipulate global simulator state, so they stay serial within one simulator.
# Regression shards each run on their own runner with their own simulator.
xcodebuild test-without-building "${common[@]}" -parallel-testing-enabled NO \
  -resultBundlePath build/RoadPrint.xcresult ${selection[@]+"${selection[@]}"} | tee build/xcodebuild.log | tail -n 80
# An -only-testing entry that matches nothing runs zero tests and still passes, and shard 3
# skips it too. Fail instead, so a renamed test cannot silently drop out of regression.
if [[ "$shard" == 1 || "$shard" == 2 ]]; then
  missing=0
  while read -r id; do
    IFS=/ read -r target class test <<< "$id"
    pattern="Test Case '-[$target.$class ${test:-}"
    if [[ -n "${test:-}" ]]; then pattern+=']'; fi
    if ! grep -qF -- "$pattern" build/xcodebuild.log; then
      echo "::error::Shard $shard ran no test for $id. Update shard_tests in Tools/ci/ios-test.sh." >&2
      missing=1
    fi
  done < <(shard_tests "$shard")
  exit "$missing"
fi
