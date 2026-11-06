# From a Linux server to your iPhone

RoadPrint is a native Swift/SwiftUI app. Apple's compiler and signing tools run only on macOS, so no code is compiled on the Paperclip server or on Windows. Every build runs on **GitHub Actions' cloud Macs**, and the finished app reaches your phone through **TestFlight**.

```
Paperclip agents (Linux server)
   │ git push (branch) → pull request
   ▼
GitHub (private repo "roadprint")
   ├─ core-tests   Linux runner, `swift test` on RoadPrintCore      every push      free
   ├─ ios-build    macOS runner, XcodeGen + xcodebuild + simulator  PRs to main      rationed
   │               tests + screenshots (uploaded as artifacts)
   └─ testflight   macOS runner, fastlane: build, sign, upload       manual / v* tag  rationed
   ▼
App Store Connect → TestFlight app on your iPhone
```

## Why this route

| Option | Verdict |
|---|---|
| **GitHub Actions + XcodeGen + fastlane** | **Chosen.** It's the most widely used no-Mac route, and agents can manage all of it (YAML, logs via `gh`, artifacts). Signing runs on CI with an App Store Connect API key and fastlane `match` |
| Xcode Cloud | 25 free compute hours a month with the Developer Program, but setup happens inside Xcode on a Mac, and agents can't read its logs from the server. Worth reconsidering if you ever get a Mac |
| Codemagic / Bitrise | Good alternatives with free macOS minutes. Keep them as a fallback if GitHub's macOS minutes run out |
| React Native / Expo (EAS) | Would avoid native tooling, but the plan chose Swift for SwiftUI Canvas, MapKit, SwiftData and CloudKit. Rejected |

**Cost:** a private repo on GitHub Free includes 2,000 Actions minutes a month. macOS minutes count 10×, so that's about **200 macOS minutes** (roughly 15–25 iOS builds); the overage is about $0.06 per macOS minute. Making the repo public would make all minutes free, but it would also publish the code.

## What the board (you) must do, in order

### Now: before any agent works
1. Create a GitHub account if you don't have one, then create a **private** repo named `roadprint`, completely empty (no README, licence or .gitignore).
2. Create a **fine-grained personal access token** limited to that one repo, with these permissions:
   - Contents: read and write
   - Pull requests: read and write
   - Actions: read and write
   - Workflows: read and write
   - Metadata: read
3. In Paperclip, open RoadPrint → Settings → Secrets and add a secret named **`GITHUB_TOKEN`** with the token as its value. Don't paste the token into chat or into an issue.
4. Tell Claude (or the CTO) the repo URL. The server repo then gets `origin`, and the token gets bound to the agents.

### Until then
The board is not paying for Apple yet. Builds stay unsigned and run on the simulator only. Each PR's `ios-build` run uploads simulator screenshots as artifacts (`screenshots`), and that is how the board reviews the app.

### Later, when the board enrolls (deferred)
5. Enroll in the **Apple Developer Program** ($99 a year). Use an individual account unless you want a company name on the App Store.
6. In App Store Connect, create the app record (bundle ID `app.roadprint.ios` or similar; the CTO will ask) and reserve the name "RoadPrint: Trucker Heatmap".
7. Create an **App Store Connect API key** (role: App Manager). Add three GitHub Actions secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8` (the contents of the .p8 file).
8. Create a second, empty private repo `roadprint-certs` for fastlane `match`, and add a `MATCH_PASSWORD` secret.
9. Install **TestFlight** on your iPhone and accept the internal-tester invite.

### Later
10. RevenueCat account and subscription products (week 11), the privacy policy page, and App Store submission (plan §11).
