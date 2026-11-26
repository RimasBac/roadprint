# ADR 0007: Android app with a shared Swift core

- Date: 2026-11-26
- Status: **Proposed.** Board, 2026-11-26: CTO review now, **no Android work before the iOS App Store launch**. After launch, the spike (Phase 0 in [docs/android/PLAN.md](../android/PLAN.md)) decides.
- Owner: CTO. Plan §3 ("Android maybe later"), §4.8, §6. AGENTS.md §7, §7b.
- Related: [ADR 0005](0005-icloud-sync.md) (sync), [ADR 0006](0006-terrain-elevation-tiles.md) (tiles), [ADR 0008](0008-android-backup.md) (Android backup).

## Context

v1 is iPhone only. AGENTS.md §7 kept Android possible from day one, and the code follows it:

| Rule (AGENTS.md §7) | State on `main` (2026-11-26) |
|---|---|
| Core free of Apple frameworks | `RoadPrintCore`: about 7,000 lines, imports only `Foundation` and `FoundationXML` (GPX). Builds and tests on Linux |
| Storage and sync behind protocols | `TripStore`, `SyncService` in core. Only `App/Storage/` imports SwiftData or CloudKit |
| Export format is the contract | GPX + versioned JSON (`docs/data-format.md`), golden fixtures |
| Purchases through entitlements | `PurchaseService` → `Entitlement` → `ProPolicy`. RevenueCat `pro` entitlement |
| Maths in core, views only draw | Projections, heat scene, card geometry, terrain rasteriser (ADR 0006 §7) are all in core |
| Tokens generated | `Design/tokens.json` → `Tokens.generated.swift`, `CardTokens.generated.swift` |

The iOS app (`App/`, about 9,400 lines of SwiftUI) is the part that has to be rebuilt. Truck drivers use Android a lot, especially in Europe and in Eastern Europe, so Android is likely to matter for growth after the iOS launch.

Since March 2026, **Swift 6.3 ships an official Swift SDK for Android** (swift.org). Java/Kotlin interop (`swift-java`, `jextract`) is usable but the Swift project still calls it work in progress.

## Decision

1. **A native Android app: Kotlin + Jetpack Compose UI, on top of the same `RoadPrintCore` compiled with the Swift SDK for Android.** There is one core and one set of core tests. Android rebuilds only the shell that `App/` is on iOS: views, location, storage, purchases, sharing.
2. **The core stays the single source of truth for every number and pixel it computes:** GPS cleaning, privacy trim (including the FNV-1a trim offset), places and roads, heat index, projections, card geometry, the terrain raster. That way share cards, exports and badges come out the same on both platforms. The cost: Swift on Android, a JNI bridge, and a bigger APK.
3. **A narrow bridge.** Kotlin calls a small façade (`RoadPrintCoreAndroid`, Swift, in a new SwiftPM target) that takes and returns **JSON or byte buffers**, never fine-grained objects. Examples: `processTrip(json) -> json`, `buildHeatScene(tripsJson, filterJson) -> sceneJson`, `renderTerrain(inputJson, tiles) -> RGBA bytes`. The JSON shapes are the ones `docs/data-format.md` already defines. The bridge is generated with `swift-java`/`jextract` or written by hand in JNI. The spike decides which.
4. **Android platform pieces (Kotlin, in `android/`):**

   | Concern | iOS (today) | Android |
   |---|---|---|
   | UI | SwiftUI, Canvas | Jetpack Compose, Compose `Canvas` drawing the core's scenes |
   | Recording | Core Location, background mode | Fused Location Provider in a **foreground service** of type `location`, started by Start Trip while the app is visible. **No `ACCESS_BACKGROUND_LOCATION`** (Play Store plan §5). So on Android 14+ the service can't restart from the background: if the OS kills the process mid-trip, recording resumes only when the driver opens the app, and the gap detection on reopen marks the trip "partially recorded" |
   | Altitude | `CLLocation.altitude` (sea level) + `CMAltimeter` | `Location.altitude` is **above the WGS84 ellipsoid**. Convert with `AltitudeConverterCompat` (AndroidX) to sea level before it reaches the core. Barometer only where the phone has one |
   | Storage | SwiftData `TripRecord` with JSON blobs | Room (SQLite), one row per trip with the same JSON blobs. Implements the same `TripStore` contract |
   | Sync / backup | CloudKit private DB (ADR 0005) | Android Auto Backup + export/import. See ADR 0008 |
   | Purchases | RevenueCat iOS / StoreKit 2 | RevenueCat Android / Play Billing, same `pro` entitlement, same `ProPolicy` |
   | Charts | Swift Charts | Compose Canvas: the elevation profile is already computed in core |
   | Zoom map | MapKit | Open question (PLAN.md Q8): MapLibre or Google Maps SDK, or leave it out of Android v1 |
   | Video card | AVFoundation | Media3 Transformer / `MediaCodec`, from the core's frame list |
   | Terrain tiles | `URLSession` behind a protocol | `HttpURLConnection`/OkHttp behind the same protocol, same base URL, same cache cap |
   | Strings | `Localizable.xcstrings` | `strings.xml` generated from the String Catalog (new `Tools/` script) |
   | Tokens, fonts, signs | generated Swift, bundled TTF/SVG | `gen-tokens.mjs` also writes Kotlin; same TTFs; signs as VectorDrawable or rendered from SVG |

5. **Same repo, new top-level `android/`** (Gradle project). `Design/`, `Tools/`, fixtures and `docs/` stay shared. The Swift core is cross-compiled in CI and packaged as `.so` files in an Android library module.
6. **The data stays the same.** Same `Trip` JSON, same `schemaVersion` rules, same UUIDs and `updatedAt` rules, same `visibility`. A file exported on one platform imports on the other. That is how drivers move between iPhone and Android (ADR 0008).
7. **Privacy rules are unchanged** (AGENTS.md §8): no speed, trimmed ends, no analytics SDK, no network except terrain tiles and the store/RevenueCat. Android adds no new data flow except Google's backup (ADR 0008).
8. **Fallback if the spike fails:** port `RoadPrintCore` to Kotlin, with the Swift tests' golden fixtures (GPX, JSON, projection goldens, terrain PNGs) as the shared spec, checked in both CI jobs. Two cores, kept in step by fixtures.

## Options considered

| Option | Verdict |
|---|---|
| **Kotlin/Compose UI + shared Swift core (Swift SDK for Android)** | **Chosen, if the spike passes.** One core, identical output. Builds on Linux, which suits the agent server and the free GitHub Linux runners |
| Kotlin/Compose UI + core ported to Kotlin | **Fallback.** Familiar Android stack and a smaller APK, but two cores to keep in step forever. Every core PR becomes two PRs |
| Skip (SwiftUI → Compose, Skip Fuse) | Rejected for now. The app is mostly custom Canvas, Charts, MapKit and AVFoundation, where translation helps least. It also adds a vendor toolchain to every iOS PR. Its JNI bridging could still be used inside option 1 |
| Kotlin Multiplatform core, used by iOS too | Rejected. It rewrites a tested, shipping core and changes the iOS app for Android's sake |
| Flutter / React Native rewrite of both apps | Rejected. It throws away the iOS app and the design work in SwiftUI |
| Wait: no Android work until there is demand | Partly kept: nothing starts, the spike included, until after the iOS launch (board, 2026-11-26; PLAN.md §1) |

## Spike exit criteria (Phase 0)

The shared-core option is kept only if all of these hold on a GitHub Linux runner and a real mid-range phone:

1. `RoadPrintCore` and its tests build for `aarch64-linux-android` and `x86_64-linux-android` with the Swift 6.3+ Android SDK, with no source changes outside `#if os(Android)` shims. Tests pass on an emulator.
2. `FoundationXML` (GPX), `Bundle.module` resources (`places.rpgeo`, `roads.rpgeo`, `areas.rppl`) and `JSONEncoder` dates give the same results as on Linux. So do the deterministic hashes: the FNV-1a trim offset (`PrivacyTrim.fnv1a`) and the terrain noise hashes (`TerrainRenderer.waterHash`, `valueNoise`). Swift's `Hasher` is seeded randomly on each launch and must never feed anything that has to match. The export golden tests pass byte for byte.
3. A Compose test screen draws the I-80 trip summary and the heat scene from core output, and the terrain raster for Brenner, within the iOS time budgets (ADR 0006: ≤ 2 s p95 for terrain, excluding download).
4. The size the core adds to the AAB download is **≤ 25 MB per ABI** (Swift runtime + Foundation + ICU + resources). Measured with `bundletool get-size total`. Also check whether `FoundationEssentials` plus `FoundationXML` is enough to avoid bundling full ICU.
5. A cold start of the core (loading the place and road indexes) takes **≤ 500 ms** on the test phone.

If any of these fail, the board picks the fallback (decision point 8) with the measurements in front of it.

## Consequences

- AGENTS.md §2 and §7 get an Android column. The CTO reviews Kotlin PRs too. A new **Android Engineer** agent (Sonnet) joins.
- The core's public API is now also an ABI for Android. Breaking changes to the façade need a bump to `RoadPrintCoreAndroid`'s version and both apps updated in the same PR.
- CI gets an `android-build` job on `ubuntu-latest` (free for the public repo): cross-compile the core, Gradle build, JVM unit tests, Compose screenshot tests (Roborazzi or Paparazzi, no emulator), and emulator smoke tests on KVM. The 4 GB agent server can't run Gradle and an emulator together, so Android, like iOS, is compiled only in CI. Agents run core tests and Kotlin lint locally.
- Store and backup work is described in [docs/android/PLAY_STORE.md](../android/PLAY_STORE.md) and ADR 0008.

## Risks

- **Swift on Android is new.** Foundation gaps on Android, toolchain bugs, NDK updates. Mitigation: the spike, `#if os(Android)` shims kept in one file, a pinned SDK version, and the Kotlin fallback.
- **APK size.** Foundation with ICU is large. Mitigations: per-ABI splits in the AAB, arm64 only for phones if Play allows the device reach, `FoundationEssentials` if the core can live with it.
- **Two UIs drift.** Mitigation: views only draw what the core computed, golden screenshots on both platforms from the same fixtures, and one `SCREENS.md` with an Android column.
- **OEM battery killers** (Samsung, Xiaomi, Huawei and others) stop foreground services. The core's gap detection already marks the trip "partially recorded". Android onboarding adds a "keep RoadPrint running" step that opens the phone's battery settings.
- **Large screens.** Apps that target API 36 can no longer force portrait on tablets and foldables (Android 16). Phone layout has to tolerate landscape and wide windows, or tablets are excluded in the Play device catalogue (PLAN.md Q11).
