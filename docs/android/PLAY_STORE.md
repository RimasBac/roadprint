# RoadPrint on Google Play: integration plan

- Date: 2026-11-26. Status: **draft for the board.** Nothing here starts before the iOS App Store launch (board, 2026-11-26), the Play Console account included.
- Goes with [ADR 0007](../adr/0007-android-port.md) (Android app) and [ADR 0008](../adr/0008-android-backup.md) (backup). The phases are in [PLAN.md](PLAN.md).
- Mirrors what we already do for Apple: `docs/BUILD_PIPELINE.md`, fastlane, TestFlight, `docs/pro.md`.

Everything marked **[board]** costs money, needs an identity, or touches accounts and secrets (AGENTS.md §6). Agents prepare exact numbered steps in a board issue and never do these themselves.

## 1. Lead times to plan around

| Item | Lead time | Why it matters |
|---|---|---|
| Play Console account verification | days to ~2 weeks | Identity (personal) or D-U-N-S number (organisation) |
| **Closed test: 12 testers opted in for 14 days in a row** | **≥ 14 days**, and it restarts if Google rejects the production request | Required for personal accounts created after 13 Nov 2023 before production access. Organisation accounts are exempt |
| Production access review | a few days | After the closed test |
| First app review | hours to ~7 days | Longer for new accounts, location and foreground-service apps |
| Merchant account (payments profile) | 1–3 days | Needed before any paid subscription can be created |

**So the account and the closed test start long before the app is finished.** The 12 testers can be the same drivers recruited for the beta (plan §12).

## 2. Account and identity [board]

1. **Account type: personal** (board, 2026-11-26; PLAN.md Q1). $25 once. The 12×14 closed-test rule applies (§1), and the store shows the board's legal name and, because the app sells subscriptions, a contact address. Check which address Play shows and whether a business address can be used instead.
2. Create the Play Console developer account **on the project's own Google account** (it exists, and the board has the address), with 2-step verification. Finish identity verification. Not before the iOS launch (AGENTS.md §7).
3. **Payments profile and merchant account:** bank account, tax info (W-8BEN for a non-US individual, or the company equivalent), and VAT where it applies. Google collects and pays VAT/GST for Play sales in most countries.
4. Add a second admin, or document a recovery path (same rule as the Apple account).

## 3. The app record [board, then agents]

1. Create the app: name **RoadPrint: Trucker Heatmap** (26 of 30 characters), default language en-US, App, Free (with in-app purchases).
2. **Package name `com.rimasbac.roadprint`**, the same as the iOS bundle ID. It can never change after the first upload.
3. **Play App Signing** (required for AABs). Google holds the app signing key. **[board]** generates the **upload key** (`keytool`), keeps an offline copy, and stores it as GitHub secrets `ANDROID_UPLOAD_KEYSTORE_B64`, `ANDROID_UPLOAD_KEYSTORE_PASSWORD`, `ANDROID_UPLOAD_KEY_ALIAS`, `ANDROID_UPLOAD_KEY_PASSWORD`. Never commit it. If it's lost, Google can reset the upload key; the app signing key stays safe with Google.
4. **The first AAB is uploaded by hand** to the internal track in Play Console. The Publishing API works only after the package exists.
5. **API access for CI [board]:** Google Cloud project → enable *Google Play Android Developer API* → service account → JSON key → GitHub secret `PLAY_SERVICE_ACCOUNT_JSON` → Play Console *Users and permissions* → invite the service account with *Release to testing tracks* and *Manage store listing* only. Production releases stay manual (board decision, the same as App Store submission).

## 4. Tracks, mapped to what we do on iOS

| Play track | iOS equivalent | Use |
|---|---|---|
| Internal testing (≤ 100 testers, available within minutes, no review) | TestFlight internal | Every finished milestone. Board and agents' test phones |
| Closed testing (email list or Google Group) | TestFlight external | Beta drivers. **The 12×14 rule runs here** |
| Open testing | public TestFlight link | Optional, before launch |
| Production, **staged rollout** (e.g. 10 % → 50 % → 100 %) | phased release | Launch and every update. Halt the rollout if Android vitals spike |

**Testers and Pro:** iOS gives TestFlight testers Pro without the paywall (ROA-124). Android can't reliably detect its track. Options: *license testers* (free test purchases that renew fast), or Play **promo codes** for a free Pro period. Recommended: license testers for the team, promo codes for beta drivers.

## 5. Policy declarations (App content) [agents draft, board submits]

| Declaration | RoadPrint answer / work |
|---|---|
| **Privacy policy URL** | `docs/privacy.html` gets an Android section: storage on the phone, Google backup (ADR 0008) in place of iCloud, terrain tiles, Google Play Billing / RevenueCat |
| **Data safety form** | Draft in `docs/android/data-safety.md`. Precise location: processed on the device, stored on the device. Terrain tile requests reveal an approximate area to the tile host (ADR 0006), so likely *approximate location, collected, not shared, not stored, needed for a feature*. Purchase history and an app user ID through RevenueCat (follow RevenueCat's Data safety guide). Encrypted in transit: yes. Deletion: in app ("Delete all data"). No ads, no analytics |
| **Location permissions** | Ask for `ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION` **while in use only**. Start Trip starts the foreground service from a visible screen, so background-location permission is not needed. **Don't declare `ACCESS_BACKGROUND_LOCATION`**: that brings in a separate declaration, a video, and a far stricter review |
| **Foreground service types** | `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_LOCATION`, service type `location`. Play Console requires a description and a **video** of the user starting a trip and the ongoing notification (the same as the iOS App Review background-location recording, plan §11) |
| **Notifications** | `POST_NOTIFICATIONS` (Android 13+) for the recording notification. The trip still records if it's denied, but the user can't see the status in the shade |
| Battery optimisation | Don't request `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (restricted by policy). Open the battery settings page with an explanation instead |
| Ads | No ads |
| Target audience | 18+. Not designed for children |
| Content rating (IARC) | Questionnaire. No user-generated content in the app, no sharing *inside* the app (sharing goes out through the system sheet) |
| Account deletion | Not applicable: there are no accounts. Say so in the form |
| Government / financial / health / news | No |
| Driver distraction | Not an Android Auto app. The same in-app rule as iOS: "Never use your phone while driving" (onboarding) |

## 6. Subscriptions (Google Play Billing via RevenueCat) [board creates, agents wire]

1. Play Console → Monetise → **Subscriptions** → one subscription, product ID **`pro`**, with two **base plans**: `monthly` (auto-renewing, 1 month, $4.99) and `yearly` (auto-renewing, 1 year, $39.99). Use Play's price templates for local prices (plan §8).
2. **Offer** on `yearly`: a 7-day free trial, eligibility *new customer acquisition* (Play's term for "never had this subscription").
3. RevenueCat: add the Android app (package `com.rimasbac.roadprint`), upload the **service account JSON** with *View financial data* + *Manage orders and subscriptions* permissions, and turn on **Real-time developer notifications** (Google Cloud Pub/Sub topic; RevenueCat gives the topic setup steps).
4. RevenueCat products `pro:monthly` and `pro:yearly` → attach to the **existing `pro` entitlement** and add them to the existing offering's annual and monthly packages. `ProPolicy` and the paywall rules in `docs/pro.md` don't change.
5. App: `RevenueCatPurchaseService` (Kotlin) with the Android public SDK key from a build config field injected by CI (`REVENUECAT_ANDROID_KEY`), like iOS. A "Manage subscription" link opens the Play subscriptions page (deep link with `sku` and `package`). "Restore purchases" calls RevenueCat `restorePurchases`.
6. Test purchases with license testers on the internal track: renewals are accelerated (monthly ≈ 5 min), so test renewal, grace period, account hold, cancel, and restore on a second device.
7. **A Pro subscription is per store.** Buying on iPhone doesn't unlock Android, because v1 has no accounts and RevenueCat's anonymous IDs differ per platform. This is open question Q3 in PLAN.md. Until it's decided, the paywall and FAQ must say so.

## 7. Store listing [Designer + agents]

| Asset | Spec | Source |
|---|---|---|
| App icon | 512×512 PNG, 32-bit, ≤ 1 MB. Adaptive launcher icon (foreground/background layers, 108 dp safe zone) | `Design/icon/` SVGs → new Android export |
| **Feature graphic** | 1024×500 JPG/PNG, **required** | New, from the App Store frame style |
| Phone screenshots | 2–8, 9:16 portrait, 1080×1920 or larger, sides between 320 and 3,840 px | `Design/appstore/` pipeline → add a Play frame. Captured from Compose screenshot tests (Roborazzi) on Linux CI with the same fixture trips as `AppStoreScreenshotTests` |
| Short description | ≤ 80 characters | "Log truck trips. Share route cards. Build a heatmap of every road you drive." |
| Full description | ≤ 4,000 characters | From the App Store text, minus iCloud wording |
| Video (optional) | YouTube link | `roadprint-app-preview` MP4 re-cut for Android |
| Category / tags | Maps & Navigation (or Travel & Local) | Board choice |
| Contact | Support email + `docs/support.html` | Exists |

## 8. CI and release pipeline (agents)

- `android-build` workflow on `ubuntu-latest`:
  - *PR*: cross-compile `RoadPrintCore` with the Swift Android SDK (cached), `./gradlew lint testDebugUnitTest`, Roborazzi screenshot checks, and an emulator smoke test (`reactivecircus/android-emulator-runner`, KVM) for record → end → summary.
  - *Integration*: full instrumented suite on API 29 and API 36 emulators.
  - *Release* (manual dispatch or `android-v*` tag): `bundleRelease`, sign with the upload key, `fastlane supply` (or Gradle Play Publisher) to the **internal** track, release notes from the milestone. Same rule as TestFlight: CTO or board starts it, once per finished milestone.
- `versionCode`: monotonically increasing CI number. `versionName` matches the iOS marketing version.
- After each internal release, read the **Pre-launch report** (automatic Firebase Test Lab runs on real devices, free) and **Android vitals** (crashes, ANRs, no SDK needed). This replaces Xcode Organizer. Still no third-party crash SDK (AGENTS.md §8).
- **targetSdk 36** (required for new apps and updates since 31 Aug 2026). Plan for **one target-SDK bump per year** (each August) as recurring work.
- `minSdk`: proposed **29 (Android 10)**. It must also be at least what the Swift Android SDK supports. The spike confirms this.

## 9. Outside services the board needs

| Service | Needed for | Cost | Status |
|---|---|---|---|
| **Google Play Console** | App record, tracks, listing, subscriptions (products, base plans, offers, prices), promo codes, license testers, order lookup and refunds, Android vitals, pre-launch report | $25 once | New [board] |
| **Google payments profile / merchant account** (inside Play Console) | Selling subscriptions, payouts, tax forms | Free; Google keeps 15 % of subscription revenue | New [board] |
| **Google Cloud project** | Service account for the Play Developer API (CI uploads, RevenueCat), Pub/Sub topic for real-time developer notifications | Free at our volume | New [board] |
| **RevenueCat** | One dashboard for both stores: subscribers, revenue charts, trial conversion, churn. Look up a customer, **grant Pro by hand** (testers, creators, a driver who moved platforms), and refund Google purchases. Webhooks if ever needed | Free under $2.5K monthly tracked revenue, then a small percentage | Exists. Add the Android app to the same project |
| **App Store Connect** | iOS subscriptions, TestFlight, review | $99/year | Exists |
| **Google Group** (or an email list) | Closed-test tester list: drivers join by joining the group | Free | New |
| **GitHub Actions secrets** | Upload key, service account JSON, `REVENUECAT_ANDROID_KEY` | Free | Exists; new secrets [board] |
| Support email | Store listings on both stores require a contact | Free | The project's Gmail account exists. A project domain is optional (2026-11-26: `roadprint.app` and `roadprint.com` are taken, and the board won't buy `roadprint.com` at $3,749. `getroadprint.com` and `getroadprint.app` were free) |
| Accountant / bookkeeping | Income tax on store payouts as an individual. The stores handle VAT in most countries, not your income tax | Varies | Personal account (Q1) |
| An Android test phone | Real drives, performance reference (PLAN.md Q10) | ~$300–400 once | New [board] |

**Not needed:** Firebase (Play vitals and the pre-launch report replace Crashlytics and Test Lab for us), Stripe or any web payments (Pro is sold only in the stores), analytics SDKs (AGENTS.md §8), a RevenueCat paywall product (we have our own paywall).

**Support tip:** show a short **Support ID** (RevenueCat app user ID) in Settings on both apps. With it the board can find a driver in RevenueCat, check their subscription, refund, or grant Pro, with no accounts in the app.

## 10. Launch checklist (Android)

- [ ] Account verified, merchant account live, upload key and service account in secrets
- [ ] Internal track build installs on the board's phone, records a real drive, restores from backup (ADR 0008 tests)
- [ ] Closed test: ≥ 12 opted-in testers for 14 consecutive days (personal account only), then apply for production access
- [ ] Data safety form, privacy policy Android section, content rating, foreground-service video submitted
- [ ] Subscriptions active. License-tester purchase, renewal, cancel and restore all tested. Paywall wording says Pro is per store
- [ ] Store listing: icon, feature graphic, screenshots, texts. Attribution (Natural Earth, terrain tile sources) in Settings
- [ ] Staged rollout plan and halt criteria: Play's bad-behaviour thresholds, a **1.09 % user-perceived crash rate** and a **0.47 % user-perceived ANR rate**. Halt well before reaching either
