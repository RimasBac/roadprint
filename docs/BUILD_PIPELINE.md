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
   ├─ testflight   macOS runner, fastlane: build, sign, upload       manual / v* tag  rationed
   └─ testflight-distribute  Linux runner, fastlane: external group   manual           free
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
6. In App Store Connect, create the app record (bundle ID `com.rimasbac.roadprint`) and reserve the name "RoadPrint: Trucker Heatmap".
7. Create an **App Store Connect API key** (role: App Manager). Add the GitHub Actions secrets `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8` (the contents of the .p8 file), plus `APPLE_TEAM_ID`.
8. Create a second, empty private repo `roadprint-certs` for fastlane `match`, and add the secrets `MATCH_PASSWORD`, `MATCH_GIT_URL` and `MATCH_GIT_BASIC_AUTHORIZATION` (see the table below).
9. Install **TestFlight** on your iPhone and accept the internal-tester invite.

### Later
10. RevenueCat account and subscription products (week 11), the privacy policy page, and App Store submission (plan §11).

## The jobs

| Job | Workflow | Runs on | Triggers | Rough cost |
|---|---|---|---|---|
| `core-tests` | `core-tests.yml` | Linux | every push | free |
| `ios-build` | `ios-build.yml` | macOS | pull requests to `main`, manual | measured: about 2.5 min per run, billed as 3 macOS minutes, so about 30 of the 2,000 free minutes |
| `testflight` | `testflight.yml` | macOS | manual, and pushed tags `v*`. Nothing else | estimated: 8 to 12 min per run, about 100 of the 2,000 free minutes |
| `testflight-distribute` | `testflight-distribute.yml` | Linux | manual, input `build_number` | free, about 1 min |

Only the CTO starts `testflight` and `testflight-distribute`.

```
gh workflow run core-tests
gh workflow run ios-build --ref <branch>
gh workflow run testflight                              # build and upload to TestFlight
gh workflow run testflight -f bootstrap_signing=true    # one time only, see below
git tag v0.1.0 && git push origin v0.1.0                # same as a manual testflight run
gh run list --workflow testflight
gh run view <run-id> --log-failed
```

`testflight` runs one fastlane lane, `beta`: match (read only) → XcodeGen → build number from `GITHUB_RUN_NUMBER` → signed build → upload to TestFlight without waiting for Apple's processing. The build number is passed to the build as `CURRENT_PROJECT_VERSION`. Its artifact `testflight-logs` holds the `.ipa` size and the fastlane and build logs. The `.ipa` itself is never uploaded.

## Distribute to the external group

Run this after build N has finished processing in App Store Connect (TestFlight shows it as "Ready to Submit"):

```
gh workflow run testflight-distribute -f build_number=N
```

It runs on Linux (no Xcode, no macOS minutes) and the fastlane lane `external_beta`. The lane creates the external group `Board device` if missing (public link on, limit 5), adds build N, submits it to Beta App Review and prints the public link in the log. No individual testers are added; anyone with the link installs through the TestFlight app. The description, "What to Test" and review notes are in `fastlane/beta/`. The job fails at the start if any secret below is empty.

## Secrets

All are GitHub Actions secrets with exactly these names. Nothing is stored in git. The workflow stops at the start with a clear message if any is empty.

| Secret | What it is | Where it comes from |
|---|---|---|
| `ASC_KEY_ID` | App Store Connect API key ID | App Store Connect → Users and Access → Integrations |
| `ASC_ISSUER_ID` | Issuer ID shown on the same page | same |
| `ASC_KEY_P8` | Full contents of the `.p8` file, including the BEGIN and END lines | downloaded once when the key is created |
| `APPLE_TEAM_ID` | 10-character team ID | developer.apple.com → Membership |
| `MATCH_PASSWORD` | Passphrase that encrypts the certificates in `roadprint-certs`. Pick a long random one | the board |
| `MATCH_GIT_URL` | HTTPS URL of the private `roadprint-certs` repo | GitHub |
| `MATCH_GIT_BASIC_AUTHORIZATION` | base64 of `username:token`, where the token is a fine-grained token with Contents read and write on `roadprint-certs` only. Create it with `printf 'user:token' \| base64` | the board |
| `BETA_CONTACT_FIRST_NAME` | First name of the Beta App Review contact | the board |
| `BETA_CONTACT_LAST_NAME` | Last name of the contact | the board |
| `BETA_CONTACT_EMAIL` | Contact email (also the tester feedback address) | the board |
| `BETA_CONTACT_PHONE` | Contact phone with country code, for example `+370...` | the board |

The four `BETA_CONTACT_*` secrets are used only by `testflight-distribute`.

## One-time signing bootstrap

After the secrets exist, the CTO runs `gh workflow run testflight -f bootstrap_signing=true` once. It runs the `bootstrap_signing` lane, which creates the distribution certificate and App Store profile and stores them, encrypted, in `roadprint-certs`. After that, `beta` only reads them. Don't repeat this unless the certificate expires or is revoked.

## Read TestFlight status without distributing

`testflight-status.yml` is a manually dispatched **ubuntu-latest** job. It uses only
`ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8`; it performs no build, group,
metadata, tester, or review mutations and does not run either distribution lane.
After this workflow reaches main, the CTO can run:

```sh
gh workflow run testflight-status -f build_numbers=3,4
gh workflow run testflight-status -f build_numbers= -f recent_limit=10
gh run list --workflow testflight-status
```

The `ios testflight_status` lane prints timestamped JSON, appends it to the GitHub
step summary, and uploads `testflight-status.json` for seven days. Selected build
numbers span marketing versions (each result includes its app version); missing
build numbers and a missing external `Board device` group are reported explicitly.
Empty selection reads only the newest page of app builds (1–50, default 10).
Selected builds, group lookup and attached builds follow pagination. A null detail
or review state means that resource is not available yet, not approval. Group
settings include link enabled, limit enabled/value, URL, and attached build numbers;
an enabled link alone does not establish that a build is approved for external use.

Rejection states are reported. The pinned API has no rejection-reason field:
review messages/reasons must be checked in the App Store Connect UI. The reporter
never fetches review contact details or testers, and emits only allowlisted fields.
API errors are summarized without response bodies or backtraces. Do not enable
Spaceship debug logging or fastlane verbose mode when using ASC credentials.
The public invitation URL is intentionally visible in this private repo's report.

API methods were checked against official Fastlane **2.241.2**, matching `Gemfile.lock`:
[GET endpoints](https://github.com/fastlane/fastlane/blob/2.241.2/spaceship/lib/spaceship/connect_api/testflight/testflight.rb),
[build fields](https://github.com/fastlane/fastlane/blob/2.241.2/spaceship/lib/spaceship/connect_api/models/build.rb),
[group fields](https://github.com/fastlane/fastlane/blob/2.241.2/spaceship/lib/spaceship/connect_api/models/beta_group.rb),
[review state](https://github.com/fastlane/fastlane/blob/2.241.2/spaceship/lib/spaceship/connect_api/models/beta_app_review_submission.rb),
and [Apple's submission attributes](https://developer.apple.com/documentation/appstoreconnectapi/betaappreviewsubmission/attributes-data.dictionary).
Only `get_apps`, `get_builds`, `get_beta_groups` and `get_builds_for_beta_group`
are called; build details and review submissions are included relationships.

`fastlane-checks` runs offline mocked reporting and pinned GET/model contract checks
on Linux for relevant pushes/PRs, with no secrets or live ASC calls:

```sh
ruby -c fastlane/Fastfile
bundle exec ruby fastlane/tests/testflight_api_contract_test.rb
```

Beta review text lives in `fastlane/beta/`. It describes current main: End Trip
processes and saves a privacy-trimmed recording; the trip list shows its summary
statistics, but a recorded-route viewer, share cards and heatmap are not available. Editing these files does not update ASC;
the CTO's separate `testflight-distribute` action publishes them when appropriate.
