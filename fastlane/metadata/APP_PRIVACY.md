# RoadPrint 1.0 App Store Connect answers

| Field | Enter |
| --- | --- |
| App Privacy → Data Collection | **No, we do not collect data from this app**. The listing displays **Data Not Collected**. |
| Export compliance → Non-exempt encryption | **No**. `ITSAppUsesNonExemptEncryption` is already `false` in `project.yml`. |
| Age rating | **None** for all content frequency questions and **No** for capability questions. Expected rating **4+**. |
| Primary category | **Navigation** |
| Secondary category | **Travel** |
| Price | **Free** |
| Alternate name if the primary is unavailable | **RoadPrint – Drive Heatmap** |

Before publishing these answers, verify the exact release commit after ROA-74 removes the temporary test-trip tool. That tool still calls Apple Maps through `App/Home/TestDrive.swift` and `MKDirections`. The trip-processing path uses bundled map data, SwiftData disables CloudKit, and the app has no analytics, purchase, or network SDK dependencies. Export and sharing use system sheets at the user's request. Apple excludes on-device processing from data collection. [Apple App Privacy details](https://developer.apple.com/app-store/app-privacy-details/) · [Temporary tool network path](https://github.com/RimasBac/roadprint/pull/50)

The release plan lists an in-app Delete all data control. The current app offers Delete trip and iOS offers Delete App, so the public pages describe those paths. If the release gains a bulk-delete control, update both pages with its actual UI label and location.

The board replaces `CONTACT_EMAIL` in `docs/privacy.html` and `docs/support.html`, enables GitHub Pages from `main` and `/docs`, and verifies both URLs above the submission step. Use the five numbered screenshots from `appstore-screenshots` for the Designer's framing pass. [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
