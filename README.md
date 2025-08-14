# Surgeon Simulator (Xcode app) — Volumetric Viewer

Native macOS app (Swift + Metal) for interactive 3D volume rendering from medical imaging data.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later
- Apple Silicon recommended

## Quick start (Xcode)

1. Clone the repo and switch to the Xcode-only branch:
   ```bash
   git clone https://github.com/Bassir/surg_sim.git
   cd surg_sim
   git checkout xcode-project
   ```
2. Open the project:
   - Double‑click `SurgeonSimulator.xcodeproj`
3. Build & Run:
   - Scheme: `SurgeonSimulator`
   - Destination: `My Mac`
   - Press `⌘R` to run

## Notes about data/assets

- Large datasets and generated volumes are intentionally not included in this branch to keep it lightweight.
- The renderer, shaders, and UI are included under `Source/` and the project is ready to build and launch.
- If you need sample data, generate it locally (see scripts in the main branch) or contact the author for a small demo volume.

## Project layout (this branch)

- `Source/` — Swift/Metal source, transfer function editor, shaders, and app UI
- `SurgeonSimulator.xcodeproj/` — Xcode project
- `.gitignore`, `README.md`

## Troubleshooting

- If Xcode prompts for developer tools or permissions, accept and retry build.
- If you see a blank render, verify a volume is being provided by the app’s data path or sample generation routine.

## Other modules

The web/Node.js pipeline and research scripts live on `main` and include large assets; they are not needed to open and run the native Xcode app in this branch.
