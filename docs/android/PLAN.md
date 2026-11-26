# RoadPrint for Android: plan

- Date: 2026-11-26. Status: **draft for the board.**
- Decisions: [ADR 0007](../adr/0007-android-port.md) (architecture), [ADR 0008](../adr/0008-android-backup.md) (backup). Store: [PLAY_STORE.md](PLAY_STORE.md).
- Source of truth for the product is still [RoadPrint_Final_Plan.md](../plan/RoadPrint_Final_Plan.md). This plan adds Android and changes nothing in iOS v1.

## 1. When

**Board decision, 2026-11-26: no Android work before the iOS App Store launch.** Until then this plan is only reviewed. No Android issues, no spike, no Play account. The only things that apply now are the AGENTS.md §7 rules for new iOS code.

| Band | Starts | Why |
|---|---|---|
| Now, until the iOS launch | CTO review of these docs. AGENTS.md §7 rules 8–9 for new code | Nothing competes with the iOS launch for agent time or board attention |
| Right after the iOS App Store launch | Phase 0 spike and the Play Console account, together | Both have long lead times: account verification, and the 14-day closed test (PLAY_STORE.md §1) |
| After the spike decision | Phases 1–4 | — |
| After Android launch | Phase 5 options (Drive sync, server, cross-platform Pro) | Driven by beta and launch numbers |

## 2. Phases

### Phase 0: spike (1–2 weeks, one engineer + CTO)
- Cross-compile `RoadPrintCore` with the Swift 6.3+ Android SDK in a GitHub Linux job. Run the core tests on an emulator.
- A minimal Kotlin app: load a GPX fixture → `processTrip` through the bridge → draw the trip map and heat scene in Compose → render Brenner terrain.
- Measure the five exit criteria in ADR 0007 on a real mid-range phone (Q10).
- **Output:** a short report and a board decision: shared Swift core, or Kotlin port.

### Phase 1: foundation (2–3 weeks)
- `android/` Gradle project, `android-build` CI, a signed internal-track upload (PLAY_STORE.md §3, §8).
- Bridge façade `RoadPrintCoreAndroid` with JSON or byte-buffer calls, and its tests.
- Generators: `tokens.json` → Kotlin, `Localizable.xcstrings` → `strings.xml`, road signs → VectorDrawable.
- Room `TripStore` with JSON blobs, the same contract tests as `SwiftDataTripStore` (shared fixtures).

### Phase 2: record and see (3–4 weeks)
- Foreground-service recording, while-in-use permission flow, the notification, gap detection on reopen, "forgot to tap End" (plan §4.2). Without background-location permission, Android 14+ doesn't let a `location` foreground service restart from the background. If the OS kills the process mid-trip, recording stops until the driver opens the app, and the gap detection on reopen marks the trip "partially recorded".
- Altitude: sea-level conversion (`AltitudeConverterCompat`) + barometer.
- OEM battery-settings step in onboarding.
- Trip summary, all trips, My Map, elevation chart, recovery sheet. Golden screenshots against the iOS fixtures.
- **Real drives** with the board's Android phone (Q10).

### Phase 3: cards, Pro, backup (3–4 weeks)
- Share cards in every style, including Terrain (tile fetch + cache) and the video card (Media3).
- Share targets: system sheet, Instagram Stories, TikTok.
- RevenueCat Android, paywall rules from `docs/pro.md`, license-tester purchases.
- ADR 0008: backup archive, backup rules, the "Moving to a new phone" flow, iPhone ↔ Android round-trip tests.

### Phase 4: store and beta (≥ 3 weeks, mostly waiting)
- Closed test with ≥ 12 drivers for 14 days (if personal account), then production access.
- Data safety form, privacy policy Android section, foreground-service video, listing assets.
- Staged rollout to production.

**Total:** roughly 12–16 weeks of agent work after the spike, plus Play's waiting periods. That's a little shorter than iOS v1 (plan §10), because the core, the design and the data pipeline already exist.

### Phase 5: later options (separate decisions)
- Google Drive sync (ADR 0008 option B).
- Own server: cross-platform sync, Pro on both stores, social (plan §6, AGENTS.md §7b).
- Terrain tile proxy (ADR 0006 §6). Android makes it more attractive: one endpoint for both apps.

## 3. Changes to existing docs when the board accepts

- **AGENTS.md** §1 platform line, §2 folder table (`android/`, verified by `android-build`), §5 (Android Engineer), §6 board-only items (Play Console, Google Cloud, upload key, merchant account), §7 becomes "Android rules".
- **Plan** §3, §4.8 (Android no longer only "out of scope"), §6 (backup table, Android column), §9 tech stack, §11 checklist.
- **docs/BUILD_PIPELINE.md**: Android section.
- **docs/design/SCREENS.md**: Android column (system permission prompts, notification, back gesture, battery step).
- **docs/privacy.html**, **docs/support.html**: Android sections.

## 4. Working on two apps

Logic is written once. Screens, platform glue and store work are written twice.

| Written once (shared) | Written per platform |
|---|---|
| `RoadPrintCore` (about 7,000 of 16,400 lines today): cleaning, privacy trim, places and roads, heatmap, projections, card layout, terrain raster, badges, `ProPolicy`, export format | Screens: SwiftUI and Compose (`App/` is about 9,400 lines today) |
| `Design/` tokens, fonts, road signs; strings (generated for both) | Location, storage, purchases, sharing, video export, notifications |
| Fixtures, `Tools/` data prep, docs | Store work: screenshots, listing, review, policy forms, product and price changes |
| | Device testing and release, on two schedules |

**Expected extra cost per change:**

| Kind of change | Cost compared with iOS only |
|---|---|
| Core only (better GPS cleaning, a new badge, a trim fix) | about 1.1× |
| Typical feature (a new filter, a new card style) | about 1.4–1.6× |
| UI or platform feature (a new screen, widget, Live Activity) | close to 2× |

Agents write both versions, so the extra cost is mostly agent runs and CI. The real bottleneck is the board: two test installs per milestone, two store reviews, two screenshot approvals, two sets of store products.

### 4.1 Rules that keep it from doubling (added to AGENTS.md §7)

1. **Readers before writers** (AGENTS.md §7 rule 8). Readers reject a trip `schemaVersion` or archive `archiveVersion` newer than they know. A new version ships as a *reader* in both apps first. Writing starts once the reader is in a store release on **both** platforms and the board agrees (normally one release later). Otherwise moving between iPhone and Android, syncing to an older second iPhone, or restoring an older backup breaks. Optional fields that old readers can ignore need no new version, but an older app that re-saves the trip drops them.
2. **Parity rule: iOS leads, Android follows within one milestone.** A feature issue is done when iOS ships it and an Android follow-up issue exists in the next milestone. Exceptions (iOS-only features such as Live Activity) are written into `SCREENS.md`.
3. **Screen state is decided in the core** (AGENTS.md §7 rule 9). The core decides display values (units converted, rounded, ready to format), which empty, error or locked state applies, paywall decisions, and the recording state machine. User-facing strings stay in each app's string catalogue (String Catalog on iOS, `strings.xml` generated from it on Android), keyed by those core values. A screen on either platform only maps values to text and lays them out. First candidates to move, after the iOS launch: `App/Home/TripFormatting.swift` and the decision logic in `App/Home/RecordingModel.swift`.
4. **One issue, three parts.** The CTO splits a feature into core + iOS + Android sub-issues. The core part merges first, with tests. Each UI part is small.
5. **The core is a contract for two apps.** A core PR passes iOS and Android CI. A change to the Android bridge façade updates both apps in the same PR.
6. **Same fixtures, golden screenshots on both apps.** Differences show up in CI, not in board review.

### 4.2 If UI duplication still hurts

Review Skip (SwiftUI → Compose) for simple forms and settings screens only (ADR 0007 rejected it for the drawing-heavy screens). Decide with real numbers from the first two Android milestones.

## 5. Open questions for the board

Ordered by how soon they block work.

| # | Question | Why it matters | Proposed answer |
|---|---|---|---|
| Q1 | **Play account: personal or organisation?** | Organisation skips the 12-testers-for-14-days rule and shows a company name instead of yours, but needs a legal entity and a D-U-N-S number | **Decided (board, 2026-11-26): personal**, on the project's own Google account (the board has it). So the 12×14 closed test applies: recruit at least 12 Android drivers before Phase 4 |
| Q2 | **Start Android now or after the iOS launch?** | Agent time and board attention are shared with the iOS v1 launch | **Decided (board, 2026-11-26): after the iOS launch**, the spike and the Play account included |
| Q3 | **Pro across platforms?** | A driver who pays on iPhone and moves to Android pays again. Fixing it needs accounts (Sign in with Apple/Google + RevenueCat app user ID), which v1 avoids | v1: Pro is per store, said clearly in the paywall and FAQ. Revisit with Q14 |
| Q4 | **Backup: is Auto Backup + export enough for Android v1?** | No live sync like iCloud. Restore can be up to a day old | Yes (ADR 0008). Drive sync only if beta data shows a need |
| Q5 | **Shared Swift core or Kotlin port?** | The long-term maintenance model | Decided by the spike measurements (ADR 0007) |
| Q6 | **Feature parity at Android launch?** | The video card and Terrain are the Pro value. The MapKit zoom view has no equivalent | Full parity for cards and Pro. The zoom view may follow (Q8) |
| Q7 | **Launch region and Android share there?** | Android share among drivers is high in Europe. This affects the plan §13 launch-region choice and the ordering | Use the beta recruiting channel to ask drivers which phone they use |
| Q8 | **Zoom map on Android: MapLibre (+ tile host), Google Maps SDK, or none at first?** | Google Maps needs an API key and sends map use to Google. MapLibre needs a tile source (cost or a self-hosted proxy). Both are new network use (AGENTS.md §8) | None at Android launch. Decide with the ADR 0006 tile proxy |
| Q9 | **Terrain tile proxy now?** | Without it, both apps send tile requests (with the user's IP) straight to AWS. With it, there's one small service to run | Keep direct (as approved), revisit before Android launch |
| Q10 | **Test devices** | Real drives need an Android phone. Performance targets need a "mid-range" reference, like the iPhone 12 for iOS | Board buys one mid-range Samsung (most common among drivers) + uses a Pixel emulator in CI |
| Q11 | **Tablets and foldables?** | Android 16 ignores portrait-only locks on large screens for apps targeting API 36 | Phone-first layout that tolerates landscape. Exclude tablets in the device catalogue only if layout costs too much |
| Q12 | **Data safety wording for OS backup and terrain tiles** | A wrong form can get the app removed. Google's definitions differ from Apple's privacy labels | Draft from Google's definitions. Board reviews before submitting |
| Q13 | **Minimum Android version** | Lower reaches more old phones in the cab, but costs testing and may clash with the Swift SDK minimum | minSdk 29 (Android 10), confirmed by the spike |
| Q14 | **Is Android the trigger for a server?** | Cross-platform sync, Pro on both stores, a web dashboard and social all need one (plan §6). Running one means accounts, GDPR duties and cost | Not for Android v1. Review after 3 months of combined numbers |
| Q15 | **Pricing parity** | Play and Apple local prices differ. Fees are similar (Apple 15 % in the Small Business Program, Google 15 % on subscriptions), but check both before launch | Same USD prices, Play price templates for local prices |
| Q16 | **Version numbers and release cadence** | Two apps, one core. Should a core fix ship to both at once? | Same marketing version, separate build numbers. Core fixes go to both apps in the next milestone |
| Q17 | **Who owns Android in the agent company?** | New skills (Kotlin, Gradle, Play policy). The CTO reviews both | One Android Engineer agent (Sonnet). CTO review. Designer adapts store assets |
| Q18 | **Google's 2026 developer verification** (for apps outside Play) | Not needed for Play-only distribution, where the Play Console account is already verified | Play only. No APK downloads outside Play |
