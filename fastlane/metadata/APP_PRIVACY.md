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

RoadPrint processes trips on the iPhone, and iCloud sync is on by default in the release build. CloudKit syncs trips to the user's private iCloud database. The developer has no access to that database and uses no third-party services that can read it. Under Apple's definition of collection, this private sync and on-device trip processing are not collection, so trips, routes and locations stay out of the App Privacy answers; only RevenueCat's purchase data is declared. Export and sharing use system sheets at the user's request. [Apple App Privacy details](https://developer.apple.com/app-store/app-privacy-details/) · [CloudKit private database](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase)

The support and privacy contact is roadprint.info@gmail.com (in `docs/privacy.html` and `docs/support.html`). The board enables GitHub Pages from `main` and `/docs`, and verifies both URLs above the submission step. Use the five numbered screenshots from `appstore-screenshots` for the Designer's framing pass. [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
