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

RoadPrint processes trips on the iPhone, and iCloud sync is on by default in the release build. CloudKit syncs trips to the user's private iCloud database. The developer has no access to that database and uses no third-party services that can read it. Under Apple's definition of collection, this private sync and on-device trip processing qualify for **Data Not Collected**. Export and sharing use system sheets at the user's request. [Apple App Privacy details](https://developer.apple.com/app-store/app-privacy-details/) · [CloudKit private database](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase)

The support and privacy contact is roadprint.info@gmail.com (in `docs/privacy.html` and `docs/support.html`). The board enables GitHub Pages from `main` and `/docs`, and verifies both URLs above the submission step. Use the five numbered screenshots from `appstore-screenshots` for the Designer's framing pass. [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
