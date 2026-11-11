# SwiftUI Component Preview

A standalone Codex skill that discovers a project's SwiftUI sources and helps Codex adapt the requested real component into a local fixture. Render macOS-compatible components as PNGs using a detached `NSHostingView`, compare images in an offline HTML gallery, or build an interactive native preview window. PNGs and galleries can appear in Codex's right panel; the live preview is a separate macOS window. Optional framing in static renders is decorative.

## Requirements

macOS 14 or later, Xcode command-line tools, and Swift 6. Project onboarding, galleries and live builds additionally require Python 3.8 or later. No third-party packages. The helpers execute supplied Swift code with your normal permissions, so use trusted, self-contained fixtures with synthetic data. Static actions can be inert; live fixtures can use view-local state, validation and navigation. macOS-compatible SwiftUI components share the same fixture API across projects. UIKit-only components need an iOS Simulator/Canvas workflow; project modules, assets and String Catalogs need an explicitly adapted build.

## Install from a GitHub checkout

Copy this `swiftui-component-preview` directory into `${CODEX_HOME:-$HOME/.codex}/skills/`. Keep `SKILL.md`, `agents/`, `scripts/`, and `assets/` together. Refresh Codex's skill list or restart Codex, then invoke `$swiftui-component-preview` or ask for a SwiftUI component render. This repository folder is a skill package; it does not require an MCP server or a plugin manifest.

Each developer installs the same directory in their own Codex skill location. There are no personal project paths, per-developer preferences, or machine-specific settings to edit. Use the skill from any project root; the first preview request discovers the project and has Codex inspect and adapt the requested component, including its existing preview inputs. It saves the fixture and `.swiftui-preview/config.json` in that project, never in the installed skill. The configuration uses relative paths and moves with a checkout. Source or fixture edits invalidate the saved hashes and require inspection and adaptation again. Codex handles routine adaptation; unsupported platform or dependency needs are reported explicitly.

For example, after Codex prepares a genuine fixture:

```bash
python3 "<skill-directory>/scripts/bootstrap.py" discover --root "<project-root>"
python3 "<skill-directory>/scripts/bootstrap.py" configure --root "<project-root>" \
  --project "Package.swift" --source "Sources/StatusCard.swift" \
  --fixture ".swiftui-preview/fixtures/StatusCard.swift" --component StatusCard
python3 "<skill-directory>/scripts/bootstrap.py" run --root "<project-root>" \
  --mode render --output "/absolute/task-output/card.png" --width 480 --height 320
```

Discovery reads text only and does not evaluate SwiftPM manifests, plugins or build commands. Configuration records the agent's selected paths and source/fixture hashes; it cannot prove the adaptation is faithful. Bootstrap rejects existing output paths, unsafe selected paths, symlinks and malformed or stale configuration. Read [SKILL.md](SKILL.md) for first-use selection, adaptation and subsequent previews.

## Try the example

From this directory:

```bash
mkdir -p /tmp/component-renders
bash scripts/render.sh assets/ExampleFixture.swift /tmp/component-renders/example.png 480 320 light en_US --frame
bash scripts/render.sh assets/ExampleFixture.swift /tmp/component-renders/example-dark.png 480 320 dark en_US
bash scripts/gallery.sh assets/ExampleFixture.swift /tmp/component-renders/gallery.html 480 320 en_US "Account preferences"
```

The framed example is 528 × 408 pixels; its content viewport remains 480 × 320. The unframed example is 480 × 320. See [SKILL.md](SKILL.md) for the fixture entry point, resource limitations, and presentation workflow.

Open `gallery.html` in a browser to select Light or Dark and toggle the decorative frame. All four images are embedded: no server, network access, or downloaded assets are needed by the gallery itself. Its controls switch actual SwiftUI renders; controls inside the image remain static. Codex can open the gallery in its right panel using `open_in_codex` with `target: "browser"` when supported. Local-file support varies by browser; a permitted local preview server can serve an artifact-only directory on `127.0.0.1`. See the skill instructions for that fallback.

To build an interactive sample (without launching it):

```bash
bash scripts/live.sh assets/LiveExampleFixture.swift \
  "/tmp/component-renders/SwiftUI Preview.app" 640 480 en_US
```

The `.app` path must be new and its parent must exist. Open the generated app when launch is authorized and permitted. Use Get started, edit the synthetic fields, try the simulated error, continue to success, and go Back. Native developer controls offer System/Light/Dark, initial/English/Russian locales, and Reset outside the content viewport. Locale injection uses resources supplied by the fixture; it does not add translations. Reset recreates view-local state and does not undo effects elsewhere. Source edits require rebuilding at a new path. See [SKILL.md](SKILL.md) for isolation boundaries and resource limitations.

To verify the renderer and argument handling on a Mac:

```bash
bash tests/smoke.sh
python3 tests/gallery.py
bash tests/live.sh
python3 tests/bootstrap.py
python3 tests/bootstrap_render.py
```

The tests use temporary files, check PNG dimensions and distinct theme images, reject invalid arguments, and verify failure cleanup. The gallery test also verifies title escaping, quoted paths, and preservation of existing output on compilation/render failures. The live test builds without launching, checks bundle metadata and an executable, rejects invalid/existing outputs, and verifies cleanup after compiler failures. Each test removes its fixtures and compiled binaries on exit. Generated images and binaries do not belong in the distributable skill.

## License

Distributed under the [MIT License](LICENSE).
