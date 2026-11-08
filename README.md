# RoadPrint

An iPhone app for truck drivers that records trips like Strava, turns them into share cards, and builds a heatmap of every road driven.

- **Plan (source of truth):** [docs/plan/RoadPrint_Final_Plan.md](docs/plan/RoadPrint_Final_Plan.md)
- **Mockups:** [docs/plan/mockups/](docs/plan/mockups/)
- **How builds reach the iPhone:** [docs/BUILD_PIPELINE.md](docs/BUILD_PIPELINE.md)
- **Rules for AI agents:** [AGENTS.md](AGENTS.md)

The code is built by a Paperclip company of AI agents. The human owner is the board.

## Build and CI

Code is compiled and tested only on GitHub Actions: `core-tests` (Linux, every push), `ios-build` (macOS, pull requests) and `testflight` (macOS, manual or `v*` tag). Jobs, commands, secrets and costs are in [docs/BUILD_PIPELINE.md](docs/BUILD_PIPELINE.md).
