# RoadPrint: rules for every agent

Read this before touching the repo. The rules apply to every agent in the RoadPrint company.

## 1. What we are building

- **Product source of truth:** [docs/plan/RoadPrint_Final_Plan.md](docs/plan/RoadPrint_Final_Plan.md). If a task conflicts with the plan, follow the plan and flag the conflict in the issue.
- **Visual target:** [docs/plan/mockups/](docs/plan/mockups/) (trip summary, share cards, heatmap). Colours and fonts are in plan §5.1.
- **Visual plan:** [docs/design/DESIGN_PLAN.md](docs/design/DESIGN_PLAN.md) (signature, the two themes, the five card styles, the feel standard in [docs/design/FEEL_STANDARD.md](docs/design/FEEL_STANDARD.md)).
- **Screen list:** [docs/design/SCREENS.md](docs/design/SCREENS.md) (every page, sheet, alert and system prompt for v1).
- **Platform:** a native iPhone app in Swift and SwiftUI. iPhone only for v1.
- **Definition of done:** plan §15.
- `docs/archive/` holds older plan versions. Read them for background only; don't build from them.

## 2. Where you run and what you can verify

You run on a **Linux server (aarch64)**. It has a pinned **Swift 6.2.4** toolchain for local core tests, Node and Python. Apple frameworks still require GitHub Actions macOS runners. Run `bash Tools/ci/check.sh` before pushing; local compilations are serialized to protect the 4 GB server. How a commit reaches the iPhone is described in [docs/BUILD_PIPELINE.md](docs/BUILD_PIPELINE.md).

So the code is split so that most logic can be tested cheaply:

| Folder | What goes there | Imports allowed | Verified by |
|---|---|---|---|
| `RoadPrintCore/` | A Swift package with all pure logic: GPS cleaning, Douglas–Peucker, privacy trim, projections, geohash heat index, country/region lookup, units, badges and milestones, trip model DTOs, GPX/JSON export | `Foundation` only. No UIKit, SwiftUI, MapKit, CoreLocation, SwiftData or CloudKit | Local `swift test`, then one scoped Linux PR check |
| `App/` | The iOS app target: SwiftUI views, CoreLocation, SwiftData + CloudKit, StoreKit/RevenueCat, MapKit, Canvas rendering | Anything on iOS | `xcodebuild` on a **macOS** CI runner: rationed minutes |
| `project.yml` | The XcodeGen spec that generates the Xcode project on CI | n/a | macOS CI |
| `Tools/` | Data-prep scripts (Natural Earth → compact bundled format, legendary-road zones, sample trips) | Node or Python | Run on the server |
| `fastlane/` | Lanes for build, screenshots and TestFlight | n/a | macOS CI |
| `Design/` | SVG art and the design system: `tokens.json`, app icon, custom symbols, road-sign templates, badges, share-card art, illustrations, App Store frames | n/a | PNG previews checked by eye; the board approves the icon and card styles |

Rules that follow from this:
- **Push logic down into `RoadPrintCore`** whenever it doesn't need an Apple-only framework. Code that can be tested on Linux is far cheaper to get right.
- **Never commit `.xcodeproj` or `.xcworkspace`.** They're generated from `project.yml` with XcodeGen.
- **Never claim that iOS code compiles or works** unless a macOS CI run on your commit says so. Link the run in the issue.

## 3. Git workflow

- Use the **Paperclip-provided task worktree** and branch. Do not switch the shared checkout or create ad-hoc `/tmp` worktrees. The project uses `origin/main` and `/data/workspaces/tasks`. If a task unexpectedly starts in the shared checkout, stop editing and report the workspace problem.
- Local commits are cheap. Push one coherent, locally checked change and open one PR per issue; include the `ROA-…` identifier, what changed and verification evidence.
- Register it before handing over the issue: `python3 Tools/automation/client.py watch PR_NUMBER`. Exit after submission. The coordinator will wake the implementer on failure and the CTO when initial checks pass. Never keep an agent alive polling CI or end a wait without a registered continuation.
- The **CTO independently reviews** the exact PR head, including required screenshot evidence. Accept with `python3 Tools/automation/client.py approve PR_NUMBER FULL_SHA --reason 'review findings'`. The reviewer must not be the implementing agent; CTO-authored work needs board approval.
- The integration service combines at most two approved changes, tests the exact combined commit, and promotes it atomically to `main`. This is the authorized exception to manual PR merging. Agents never push to `main` or merge their own PRs. A changed head needs new review; a changed base needs new integration tests.
- Major visual changes still need selective screenshot review under `docs/design/FEEL_STANDARD.md` §8. Initial quick CI is not full iOS verification or visual approval. Release remains a separate milestone decision.
- The public remote is `origin` = https://github.com/RimasBac/roadprint. Existing `gh` authentication and project token bindings are provided by Paperclip; never print credentials.

## 4. Fast feedback and complete validation

- Local: `bash Tools/ci/check.sh` runs static checks, coordinator tests and core Swift tests. `--static` and `--core` select a subset. Use at most two compiler jobs.
- PR: one `core-tests` check, scoped to changed files; relevant iOS changes get `quick` compilation, unit tests and smoke tests. No duplicate branch-push check.
- Need feedback on one screen? Dispatch `ios-build` with `evidence=targeted` and `test_filter=RoadPrintUITests/Class[/test]`; register the PR and exit. Request screenshots with `routine` or the full device matrix with `full`.
- Integration: full core, iOS functional regression and fastlane checks on the exact approved candidate. Benchmarks and preview generation run separately for relevant main changes.
- TestFlight remains CTO/board initiated once per finished milestone. Never release on quick checks alone. On failure, read the complete failure log and fix observed defects in one batch.
- Standard GitHub-hosted runners are free for this public repo. Optimize feedback latency and agent usage. Do not change billing, secrets or repository visibility without board instruction.
- See `Tools/automation/README.md` and `docs/BUILD_PIPELINE.md` for operation and recovery. No persistent Mac worker is planned.

## 5. Model budget and responsibilities

Paperclip's live agent configuration is the source of truth for models. Currently CEO, CTO and Designer use Claude Opus 5.5; iOS and Platform Engineers use Claude Sonnet 5.5. The team shares a subscription. The CEO handles priorities, the CTO architecture and independent review, engineers implementation, and the Designer visual assets and visual review. Do not spend model runs polling CI or doing mechanical merge work. Keep runs focused; stop on quota exhaustion and resume through Paperclip.

## 6. Things only the human board can do

Never try these yourself. Create an issue assigned to the board with exact, numbered steps:
- create the GitHub repo or tokens, or change repo settings or secrets
- Apple Developer enrollment, App Store Connect app record, bundle ID, API keys, certificates
- RevenueCat account, App Store subscription products, prices, tax and banking
- installing TestFlight builds and test drives in a real vehicle
- App Store submission, privacy policy hosting, trademark or domain purchases
- anything that costs money

## 7. Keep Android possible

v1 is iPhone only, but an Android version may follow (plan §3). These rules keep that from becoming a full rewrite. They cost nothing on iOS, and the CTO checks them in review.

1. **`RoadPrintCore` stays free of Apple frameworks** (§2). All pure logic goes there, so it can be compiled with Swift for Android or ported to Kotlin using its tests as the spec.
2. **Storage and sync sit behind protocols** (for example `TripStore` and `SyncService`). SwiftData + CloudKit is one implementation. Feature code never imports SwiftData or CloudKit directly; only the storage layer does.
3. **The export/import format is the cross-platform contract.** GPX plus a versioned JSON schema (`schemaVersion` field), documented in `docs/data-format.md`, with tests for the round trip and for reading older versions.
4. **Purchases go through RevenueCat entitlements** (for example `pro`), never raw StoreKit product checks in feature code.
5. **Projection, layout and heatmap math live in the core.** Views only draw what the core computed, so an Android Canvas can reuse the same results.
6. **Design values come from `Design/tokens.json`,** and Swift constants are generated from it, never hard-coded.
7. **Domain models in the core are plain value types** (structs, enums, `Codable`), not SwiftData `@Model` classes. The app maps them to and from storage.

## 7b. Keep social possible

v1 has no social features and no server (plan §4.8, §6), but the board wants them possible later (ROA-6). These rules cost nothing now. The CTO checks them in review.

1. **Stable IDs and timestamps.** Every trip, badge award and milestone has a UUID, `createdAt` and `updatedAt`, so a future server can merge and deduplicate them.
2. **A local profile, no login.** A `UserProfile` value type in the core (local user ID, display name, unit, starting career miles), kept separate from trips. No accounts in v1.
3. **One privacy filter for everything that leaves the trip.** The core has a single function that turns a trip into a `TripShareSummary` (stats, places, badges, road sign, and the route only if allowed, already trimmed and coarsened, never speed). Share cards render only from this summary, never from the full trip, so a future feed reuses the same privacy rules.
4. **A visibility field from day one.** Trips carry `visibility` (an enum; v1 uses only `private`). It is part of the export schema.
5. **Derive, don't count.** Badges, career totals and the heat index are computed from stored trips, not kept as separate counters, so they can be recomputed on any device or server.

## 8. Hard rules

- **Never commit secrets** (API keys, `.p8` files, certificates, tokens). Secrets live in GitHub Actions secrets or Paperclip secrets, set by the board.
- **Privacy is a product feature.** Follow plan §4.2 and §5.4: no speed stored, trip ends trimmed, no data leaves the phone except to the user's own iCloud. One exception, approved by the board on 2026-11-24 ([ADR 0006](docs/adr/0006-terrain-elevation-tiles.md)): the Terrain card downloads public elevation tiles for the card's area, with no identifiers and never the route. No other network use without board approval. No analytics SDKs without board approval.
- **No new third-party dependencies** without a line in the PR explaining why. RevenueCat is pre-approved.
- **Map data attribution:** keep Natural Earth (and OSM, if used) credits in Settings and in `Tools/README.md`.
- **English strings go in a String Catalog** from day one (plan §7).
