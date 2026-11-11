# App icon: Night road

A short piece of the RoadPrint line (DESIGN_PLAN §1): a glowing amber route that climbs over a pass and rolls on, from a dashed approximate start to a bright end, on the night ground `#14161c`.

| File | iOS appearance |
|---|---|
| `roadprint-icon-any.svg` → `AppIcon.png` | Default (opaque, no alpha) |
| `roadprint-icon-dark.svg` → `AppIcon-Dark.png` | Dark (transparent; iOS supplies the dark tile) |
| `roadprint-icon-tinted.svg` → `AppIcon-Tinted.png` | Tinted (grayscale on transparent; iOS applies the tint) |

PNGs are 1024×1024, rendered from these SVGs with sharp (librsvg). The default PNG is flattened onto `#14161c` with the alpha channel removed, as App Store Connect requires.
