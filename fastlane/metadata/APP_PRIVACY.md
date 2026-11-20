# RoadPrint 1.0 App Store Connect answers

| Field | Enter |
| --- | --- |
| App Privacy → Data Collection | **Yes**: RevenueCat checks the Pro subscription. Declare **Purchases → Purchase History** and **Identifiers → Device ID** (RevenueCat's anonymous ID), each used for **App Functionality**, **not linked to the user's identity**, **not used for tracking**. Everything else is not collected. |
| Export compliance → Non-exempt encryption | **No**. `ITSAppUsesNonExemptEncryption` is already `false` in `project.yml`. |
| Age rating | **None** for all content frequency questions and **No** for capability questions. Expected rating **4+**. |
| Primary category | **Navigation** |
| Secondary category | **Travel** |
| Price | **Free**, with the RoadPrint Pro subscriptions (monthly and yearly) as in-app purchases |
| Alternate name if the primary is unavailable | **RoadPrint – Drive Heatmap** |

**Pro ships in 1.0 (board, 2026-11-20).** RevenueCat receives purchase history and an anonymous app user ID, hence the Data Collection answer above. Verify it against RevenueCat's current App Store data-disclosure guidance before submitting. Add both subscriptions to the 1.0 version under In-App Purchases and Subscriptions: Apple reviews a first subscription together with an app version.

Before publishing these answers, verify the exact release commit after ROA-74 removes the temporary test-trip tool. That tool still calls Apple Maps through `App/Home/TestDrive.swift` and `MKDirections`. The trip-processing path uses bundled map data, SwiftData disables CloudKit, and the app has no analytics SDK. Its only network SDK is RevenueCat, for the Pro subscription (declared above). Export and sharing use system sheets at the user's request. Apple excludes on-device processing from data collection. [Apple App Privacy details](https://developer.apple.com/app-store/app-privacy-details/) · [Temporary tool network path](https://github.com/RimasBac/roadprint/pull/50)

The release plan lists an in-app Delete all data control. The current app offers Delete trip and iOS offers Delete App, so the public pages describe those paths. If the release gains a bulk-delete control, update both pages with its actual UI label and location.

The support and privacy contact is roadprint.info@gmail.com (in `docs/privacy.html` and `docs/support.html`). The board enables GitHub Pages from `main` and `/docs`, and verifies both URLs above the submission step. Use the five numbered screenshots from `appstore-screenshots` for the Designer's framing pass. [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
