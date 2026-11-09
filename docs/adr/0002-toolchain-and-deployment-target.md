# ADR 0002: toolchain, deployment target and bundle ID

- Date: 2026-11-06
- Status: Accepted (CTO), [ROA-13](/ROA/issues/ROA-13)

## Decision
- **Deployment target: iOS 18.0, iPhone only.** iOS 18 runs on exactly the same iPhones as iOS 17 (XS/XR and later), so it costs no devices, and it gives us the fixed SwiftData stack (history tracking, `#Index`, fewer CloudKit-sync bugs), the newer SwiftUI MapKit and Canvas APIs, and Swift Charts improvements. iOS 17 users who never updated are a small, shrinking group. Revisit at v1 launch if install data says otherwise.
- **Toolchain: Swift 6.2 (Xcode 26.x).** App Store uploads must be built with the iOS 26 SDK, so CI builds on the GitHub `macos-26` image with the newest stable Xcode 26.x pinned by path in the workflow. Linux CI uses the official `swift:6.2-noble` image so both sides compile with the same compiler line.
- **`RoadPrintCore` tools version: `// swift-tools-version:6.0`, Swift 6 language mode.** Pure Foundation code has no reason to opt out of strict concurrency. The tools version stays at 6.0 so a slightly older Linux or Android Swift toolchain can still build it (AGENTS.md §7).
- **Bundle ID: `com.rimasbac.roadprint`.** Test targets use `com.rimasbac.roadprint.tests` and `com.rimasbac.roadprint.uitests`.
Changed 2026-11-09: the original ID (`app` + `.roadprint.ios`) was already registered by another Apple developer.

## Upgrading
Bump the Linux image tag, the Xcode path and this ADR in one PR. A green `core-tests` and `ios-build` on that PR is the proof.
