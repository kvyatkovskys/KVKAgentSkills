# Changelog

Notable changes per skill. Versions are the `metadata.version` in each skill's `SKILL.md`; a Claude Code plugin's version in `.claude-plugin/marketplace.json` is bumped whenever one of its skills changes.

## Unreleased

### Repository

- Claude Code marketplace groups skills into plugins; `swiftui-component-preview` is in `apple-dev`.
- `tests/run-all.sh`, `tools/validate.py`, CI, a skill template and `tools/new_skill.py`.

### swiftui-component-preview 1.1.0

- Claude Code support: agent-neutral instructions, output selection rules (`png`, `gallery`, `live`), detail moved to `references/`.
- `fit` sizing for PNG renders.
- Live preview: resizable window with a glass control bar, optional separate live fixture, `refresh` to rebuild and reopen in place, richer built-in example.
- Swift 6 no longer required: Swift 5 language mode is used automatically on older compilers or on request.
- Fixture validation errors name the offending token and line.

### swiftui-component-preview 1.0.0

- Initial release: project discovery, fixture configuration, PNG renders, HTML gallery, live native window.
