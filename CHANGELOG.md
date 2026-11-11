# Changelog

Notable changes to the repository and to each skill. A skill's version is the `metadata.version` in its `SKILL.md`. A Claude Code plugin's version in `.claude-plugin/marketplace.json` is bumped whenever one of its skills changes.

## Repository

### Unreleased

- Claude Code marketplace groups skills into plugins; `swiftui-component-preview` is in `apple-dev`.
- README compatibility table: which agents are tested, which are expected to work, and what each skill needs from the agent.
- `tests/run-all.sh`, `tools/validate.py`, CI, a skill template and `tools/new_skill.py`.

## swiftui-component-preview

### 1.1.0 (unreleased)

- Claude Code support: agent-neutral instructions, output selection rules (`png`, `gallery`, `live`), detail moved to `references/`.
- `fit` sizing for PNG renders.
- Live preview: resizable window with a glass control bar, optional separate live fixture, `refresh` to rebuild and reopen in place, richer built-in example.
- Swift 6 no longer required: Swift 5 language mode is used automatically on older compilers or on request.
- Fixture validation errors name the offending token and line.
- Tests moved to `tests/swiftui-component-preview/`; they are no longer installed with the skill.

### 1.0.0

- Initial release: project discovery, fixture configuration, PNG renders, HTML gallery, live native window.
