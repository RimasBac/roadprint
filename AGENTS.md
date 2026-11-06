# RoadPrint: rules for every agent

Read this before touching the repo. The rules apply to every agent in the RoadPrint company.

## 1. What we are building

- **Product source of truth:** [docs/plan/RoadPrint_Final_Plan.md](docs/plan/RoadPrint_Final_Plan.md). If a task conflicts with the plan, follow the plan and flag the conflict in the issue.
- **Visual target:** [docs/plan/mockups/](docs/plan/mockups/) (trip summary, share cards, heatmap). Colours and fonts are in plan §5.1.
- **Platform:** a native iPhone app in Swift and SwiftUI. iPhone only for v1.
- **Definition of done:** plan §15.
- `docs/archive/` holds older plan versions. Read them for background only; don't build from them.

## 2. Where you run and what you can verify

You run on a **Linux server (aarch64)**. It has no Mac, no Xcode and no Swift toolchain, so SwiftUI, MapKit, CloudKit and StoreKit can't be compiled or run here. Every compile and test happens in **GitHub Actions**. How a commit reaches the iPhone is described in [docs/BUILD_PIPELINE.md](docs/BUILD_PIPELINE.md).

So the code is split so that most logic can be tested cheaply:

| Folder | What goes there | Imports allowed | Verified by |
|---|---|---|---|
| `RoadPrintCore/` | A Swift package with all pure logic: GPS cleaning, Douglas–Peucker, privacy trim, projections, geohash heat index, country/region lookup, units, badges and milestones, trip model DTOs, GPX/JSON export | `Foundation` only. No UIKit, SwiftUI, MapKit, CoreLocation, SwiftData or CloudKit | `swift test` on a **Linux** CI runner: free, fast, every push |
| `App/` | The iOS app target: SwiftUI views, CoreLocation, SwiftData + CloudKit, StoreKit/RevenueCat, MapKit, Canvas rendering | Anything on iOS | `xcodebuild` on a **macOS** CI runner: rationed minutes |
| `project.yml` | The XcodeGen spec that generates the Xcode project on CI | n/a | macOS CI |
| `Tools/` | Data-prep scripts (Natural Earth → compact bundled format, legendary-road zones, sample trips) | Node or Python | Run on the server |
| `fastlane/` | Lanes for build, screenshots and TestFlight | n/a | macOS CI |

Rules that follow from this:
- **Push logic down into `RoadPrintCore`** whenever it doesn't need an Apple-only framework. Code that can be tested on Linux is far cheaper to get right.
- **Never commit `.xcodeproj` or `.xcworkspace`.** They're generated from `project.yml` with XcodeGen.
- **Never claim that iOS code compiles or works** unless a macOS CI run on your commit says so. Link the run in the issue.

## 3. Git workflow

- `main` changes only through pull requests. GitHub Free can't enforce branch protection on a private repo, so it's on you: **never push to `main` directly.**
- Branch per issue: `rp/<ISSUE-KEY>-short-slug`.
- Small PRs: one issue, one reviewable change.
- Use clear commit messages, for example `core: add Douglas–Peucker simplifier`.
- Every PR description has: what changed, how it was verified (CI links), and screenshots for UI work (CI simulator screenshots are uploaded as artifacts).
- The **CTO reviews and merges**. Engineers don't merge their own PRs.
- The remote is `origin` = https://github.com/RimasBac/roadprint (private). On project tasks `GH_TOKEN` is in your environment, and `git push` and `gh` (PRs, `gh run view`) use it automatically. Never print it, and don't create other repos or remotes.

## 4. CI minutes are a budget

On a private GitHub repo the free plan gives about **200 macOS minutes a month** (macOS counts 10× against the 2,000 free minutes). Linux minutes are plentiful.

- The Linux `core-tests` job runs on every push.
- The macOS `ios-build` job runs only on pull requests to `main` and on manual dispatch. Don't push repeatedly just to re-trigger it. Batch your fixes, then push.
- The `testflight` job runs only on manual dispatch or a `v*` tag, and only the CTO starts it.
- If a macOS job fails, read the log (`gh run view --log-failed`) and fix everything you can see before pushing again.

## 5. Model budget: who does what

Each model has a limited subscription allowance, so match the work to the model:

| Agent | Model | Use it for |
|---|---|---|
| CEO | Claude Opus 5.5 (**the scarcest budget**) | Turning the plan into milestones and issues, priorities, unblocking, talking to the board. **The CEO doesn't write code or do code review.** Keep runs short |
| CTO | GPT-6 Astra (low allowance, frontier model) | Architecture, the hardest problems (projections, rendering performance, CloudKit encryption, background location), CI design, **PR review and merge** |
| iOS Engineer | GPT-6.1 Sol (main allowance) | Most implementation: SwiftUI screens, recording, storage, sync, share cards, heatmap, paywall |
| Platform Engineer | GPT-6.1 Terra | `RoadPrintCore` algorithms and their tests, `Tools/` data prep, XcodeGen, GitHub Actions, fastlane, docs, App Store metadata |

Default effort is medium. Escalate to the CTO rather than looping on a hard problem.

## 6. Things only the human board can do

Never try these yourself. Create an issue assigned to the board with exact, numbered steps:
- create the GitHub repo or tokens, or change repo settings or secrets
- Apple Developer enrollment, App Store Connect app record, bundle ID, API keys, certificates
- RevenueCat account, App Store subscription products, prices, tax and banking
- installing TestFlight builds and test drives in a real vehicle
- App Store submission, privacy policy hosting, trademark or domain purchases
- anything that costs money

## 7. Hard rules

- **Never commit secrets** (API keys, `.p8` files, certificates, tokens). Secrets live in GitHub Actions secrets or Paperclip secrets, set by the board.
- **Privacy is a product feature.** Follow plan §4.2 and §5.4: no speed stored, trip ends trimmed, no data leaves the phone except to the user's own iCloud. No analytics SDKs without board approval.
- **No new third-party dependencies** without a line in the PR explaining why. RevenueCat is pre-approved.
- **Map data attribution:** keep Natural Earth (and OSM, if used) credits in Settings and in `Tools/README.md`.
- **English strings go in a String Catalog** from day one (plan §7).
