# Board design references

Reference pictures the board drew and approved on 2026-11-10, with the scripts that made them. The written plan is [docs/design/DESIGN_PLAN.md](../../../docs/design/DESIGN_PLAN.md), the feel standard is [docs/design/FEEL_STANDARD.md](../../../docs/design/FEEL_STANDARD.md) and the screen list is [docs/design/SCREENS.md](../../../docs/design/SCREENS.md).

- `common/`: shared Python helpers for the generators, and how to render the SVGs.
- `night-highway/`: the Night Highway share card drawn from the real I-80 fixture, with and without layout guides.
- `print-card/`: the Print card (version 2): the transparent overlay SVG, previews on day, dusk and night photos, a guides version, the generator and a text-measuring helper.
- `theme-proof/`: the night and day theme palettes side by side.
- `road-signs/`: a rough first draft of the road-sign templates, `signs.json` and a contact sheet. Production signs are made in ROA-49.

**These are the board's approved references. A production asset may refine them, but a change to the signature, the two palettes or the list of card styles needs the board.**

Previews are rendered with `node Tools/design/render.mjs <file.svg> --width 540`.
