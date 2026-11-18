# RoadPrint build and integration pipeline

Current policy: 2026-11-17. RoadPrint is public. Standard hosted GitHub runners
are free; latency, reliable task continuation and model usage are the constraints.
The board does not want a persistent Mac worker. iOS compilation stays on GitHub.

## Development loop

Paperclip supplies a persistent worktree per task under `/data/workspaces/tasks`,
based on refreshed `origin/main`. Run `bash Tools/ci/check.sh` locally before
pushing. Swift 6.2.4 and its Linux dependencies are installed in the server image
and persistent toolchain directory. A global lock limits local Swift compilation
to one invocation, with two compiler jobs. Node checks catch token-generation,
literal, font and privacy-key problems before CI. Apple APIs still require Xcode.

Open one PR for one coherent issue and register it with
`python3 Tools/automation/client.py watch PR_NUMBER`. The issue key belongs in
the PR title/body/branch. The agent can exit immediately; CI completion reliably
wakes the original implementer or the CTO. Do not run a sleeping model session,
poll `gh run watch`, or write “waiting” without registering a continuation.

## Checks

| Check | When | Purpose |
| --- | --- | --- |
| Local `check.sh` | Before submission | Static checks, automation tests, Swift core tests |
| `core-tests` | PR, main, integration dispatch | Static checks always; Swift tests for core/toolchain changes or integration |
| `ios-build: quick` | Relevant PRs | Compile all test targets, app unit tests and launch/Your Data smoke tests |
| `ios-build: targeted` | Explicit dispatch | One test class or method, selected by `test_filter` |
| `ios-build: regression` | Integration candidate; unverified main changes | Full functional suite, excluding optional token screenshot gallery |
| `ios-build: routine` | Visual review | Full functional suite plus screenshot gallery |
| `ios-build: full` | Finished-screen device review | Routine plus SE/Pro Max evidence |
| `core-evidence` | Relevant main changes or dispatch | Release benchmarks, geometry and rendered map previews |
| `fastlane-checks` | Relevant PR/main changes; every integration | Offline API/reporting contract tests |

Branch pushes do not duplicate PR checks. A promoted commit that already has a
successful `ios-regression` dispatch reuses that exact proof rather than allocating
another Mac. Build-and-test logs and screenshots are retained for seven days;
failure result bundles for three days. Screenshots require actual review.

Examples:

```sh
bash Tools/ci/check.sh
gh workflow run ios-build --ref rp/ROA-123-feature -f evidence=targeted -f test_filter=RoadPrintUITests/TripSummaryEvidenceTests
gh workflow run ios-build --ref rp/ROA-123-feature -f evidence=routine
python3 Tools/automation/client.py watch 123
```

`ios-test.sh` uses `build-for-testing` followed by `test-without-building`. UI
tests remain serial because they use mutable simulator/app state. Long navigation,
video and fixture tests remain in regression instead of blocking every UI tweak.
Quick success must never be described as complete iOS validation.

## Review and integration

The CTO reviews the exact head and required visual evidence. Approval is submitted
through `client.py approve PR SHA --reason 'findings'`, authenticated as the CTO.
The implementer cannot approve their own recorded work; CTO-authored work needs
board approval. The service queues up to two approved changes, produces a batch
PR, tests its exact commit with core, regression and fastlane checks, then performs
an atomic non-force fast-forward to main. It never executes candidate code locally.
New head commits invalidate approval; changes to main require a new candidate.
Failures split batches; individual failures return to the implementer. Only this
service may use the exact-commit publication exception to manual PR merging.

Service details, recovery and tests: [automation README](../Tools/automation/README.md).
The initial rollout PR is reviewed and merged normally to establish these workflow
definitions; subsequent changes use the coordinator.

## Release to TestFlight

Release remains CTO/board initiated once per milestone. Full iOS regression on the
same SHA is required before a normal `testflight` upload. The simulator build is
unsigned and cannot replace the signed archive. Use one trigger, not both:

```sh
gh workflow run testflight --ref main
# or: git tag v0.1.0 && git push origin v0.1.0
gh workflow run testflight-distribute -f build_number=N
gh workflow run testflight-status -f build_numbers=N
```

`testflight`: match read-only → XcodeGen → signed archive → upload without waiting
for Apple processing. `testflight-distribute` and `testflight-status` run on Linux.
Only the CTO/board distributes builds or changes App Store metadata. Never print
signing credentials. Apple processing/review and real-device tests are separate
from CI success. Do not repeatedly dispatch status workflows while waiting.

Existing signing secrets remain unchanged: `ASC_KEY_ID`, `ASC_ISSUER_ID`,
`ASC_KEY_P8`, `APPLE_TEAM_ID`, `MATCH_PASSWORD`, `MATCH_GIT_URL`,
`MATCH_GIT_BASIC_AUTHORIZATION`, and the four `BETA_CONTACT_*` fields. The one-time
`bootstrap_signing=true` dispatch creates signing assets; it is exempt from the
regression requirement because it does not build/upload an app. Run it only on
the board's instruction. Historical setup instructions are preserved in
[the archived pipeline document](archive/BUILD_PIPELINE-20261116.md).
