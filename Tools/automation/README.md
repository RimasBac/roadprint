# RoadPrint delivery service

Agents work in Paperclip-managed task worktrees. Run `bash Tools/ci/check.sh`
before pushing; the server's Swift 6.2.4 wrapper serializes compilation, with two
compiler jobs. PRs run static/core checks once and a quick iOS check. The core
benchmark/preview workflow is separate. GitHub's standard public-repo runners
are free; optimize feedback time, not an obsolete private-repository minute quota.

## Submit, review, integrate

1. Implement one coherent change in the supplied workspace, make a PR mentioning
   its `ROA-…` issue, and run `python3 Tools/automation/client.py watch PR` inside
   the implementing agent's authenticated session. Register before handing over
   the issue so the original implementer receives failures. Then exit; no CI polling.
2. The service wakes the implementer on a failed current-commit check, or the CTO
   once all initial checks pass. It ignores superseded commits and duplicate
   webhook deliveries. While watched PRs or integration candidates await check
   results, the service reconciles every 60 seconds to recover missed or early
   completion events. Failed reconciliations also retry after 60 seconds.
   When idle, the service waits for a signed webhook or a local command.
3. The CTO reviews code and any required visual evidence. Accept with
   `python3 Tools/automation/client.py approve PR FULL_HEAD_SHA --reason 'review findings'`.
   Only the CTO or board can approve; an agent cannot approve its own recorded
   implementation. Because the team shares one GitHub identity, these review
   receipts live in SQLite rather than pretending to be separate GitHub users.
4. The service combines at most two approved heads in a separate integration
   checkout, opens a batch PR, and dispatches core tests, full iOS regression and
   fastlane checks on its immutable branch. Conflicts go back to the implementer;
   failed multi-change batches split into individual candidates. Single failures
   require a fresh review rather than unbounded retries.
5. With all three checks green and approvals still valid, it promotes the exact
   tested SHA using a non-force fast-forward. A concurrent `main` change prevents
   publication and causes a new candidate to be tested. The original PR heads
   are ancestors of the promoted commit, preserving history and GitHub PR linkage.
   No agent directly pushes or manually merges to `main`.
6. The CTO is notified to record task completion. TestFlight remains a separate
   milestone action. No Mac worker is required or provisioned.

Initial checks are not release proof. `quick` runs app unit tests and two smoke
classes; `targeted` takes a `Target/Class[/test]` selector. `regression` runs all
functional tests except the optional screenshot-gallery suite. `routine` adds
that suite, and `full` also checks SE and Pro Max. Preserve screenshot review for
visual work; a green run does not constitute visual approval. UI tests stay
serial within one simulator; `regression` runs as three shards on separate runners.

## Deployment and recovery

The deployed service files and database are in `/data/automation/roadprint`.
The dedicated Compose container `roadprint-coordinator` runs under `flock --no-fork`,
restarts on failure, and uses the existing GitHub CLI and Paperclip board
credential stores. It never runs PR code on the control plane. The HTTP server
binds to loopback; Caddy exposes only `/hooks/roadprint`, authenticated with GitHub
HMAC SHA-256. Automatic discovery of new PRs while idle requires a configured
GitHub webhook. The current GitHub credential cannot manage repository webhooks
(HTTP 403). Without a webhook, register new or updated PRs with `client.py watch`
to wake the service. The service also reconciles at startup and always reads
authoritative API state after an event. Missing candidate workflow dispatches
retain their five-minute redispatch cooldown.
Tokens and the webhook secret must never be committed or printed.

Check `curl http://127.0.0.1:3111/health` from the server and
`docker compose ps roadprint-coordinator` in the deployment directory. To stop merging while retaining
notifications, the board runs `python3 /data/automation/roadprint/client.py
--operator enable false` inside `paperclip-trial`. To stop all delivery, stop the
Compose coordinator service. Resume with `enable true`. Pending approvals, candidate SHA and
notification receipts survive restarts in SQLite. Back up the database using
SQLite's backup API, not a copy of a live database without its WAL.

Configuration/instruction snapshots taken before rollout are under
`/data/automation/roadprint/backups`. The previous Docker image is retained for
rollback. The Swift toolchain is stored on the persistent volume; runtime
dependencies are installed by `Dockerfile.workflow` in the deployment directory.
Operator credentials are privileged: restrict this service to this trusted company.

## Tests

`python3 -m unittest discover -s Tools/automation -p 'test_*.py'`
checks stale commits, repeated deliveries, failed delivery retries, verified review identity,
missing/failed checks, event-free check completion, idle scheduling, conflict
recovery, concurrent base changes, batch splitting and exact-SHA
non-force publication. Each retry gets a distinct candidate branch; abandoned
batch PRs and branches are cleaned up. GitHub CI provides the real Xcode integration check.
