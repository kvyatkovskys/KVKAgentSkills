# Changelog

Notable changes to the repository and to each skill. A skill's version is the `metadata.version` in its `SKILL.md`. A Claude Code plugin's version in `.claude-plugin/marketplace.json` is bumped whenever one of its skills changes.

## Repository

### Unreleased

- Claude Code marketplace groups skills into plugins; `swiftui-component-preview` is in `apple-dev`.
- README compatibility table: which agents are tested, which are expected to work, and what each skill needs from the agent.
- `tests/run-all.sh`, `tools/validate.py`, CI, a skill template and `tools/new_skill.py`.

## swiftui-component-preview

### 1.3.0 (unreleased)

- iOS and iPadOS previews through the iOS Simulator: `configure --platform ios`, then PNG, gallery, and live outputs on a chosen simulator (`--device`), with real iOS controls, `screen` sizes for whole device screens, `--scale`, UIKit allowed in fixtures, and `refresh` reinstalling and relaunching the app. Direct helpers switch with `PREVIEW_PLATFORM=ios`.
- The platform is chosen automatically at `configure`: from the component's UIKit or AppKit import, then the project's settings. Projects that target both platforms or declare none stop with an instruction to ask the user; `--platform` overrides. `discover` reports `suggested_platform`. A project with no platform evidence previously defaulted to macOS and now needs `--platform`.
- iOS live previews can also open in an ordinary Mac window with a control bar (`--live-host catalyst`, Mac Catalyst, iPad idiom), without a simulator.
- Live example fixture: the Done and Details screens now show edits made on the Profile screen instead of the initial values.

### 1.2.0

- Gallery embeds lossless WebP instead of PNG when `cwebp` is installed and the result is smaller; `PREVIEW_GALLERY_WEBP=0` opts out.

### 1.1.0

- Claude Code support: agent-neutral instructions, output selection rules (`png`, `gallery`, `live`), detail moved to `references/`.
- `fit` sizing for PNG renders.
- Live preview: resizable window with a glass control bar, optional separate live fixture, `refresh` to rebuild and reopen in place, richer built-in example.
- Swift 6 no longer required: Swift 5 language mode is used automatically on older compilers or on request.
- Fixture validation errors name the offending token and line.
- Tests moved to `tests/swiftui-component-preview/`; they are no longer installed with the skill.

### 1.0.0

- Initial release: project discovery, fixture configuration, PNG renders, HTML gallery, live native window.
