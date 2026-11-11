# Contributing

## Adding a skill

1. Scaffold it. The name is lowercase letters, digits and single hyphens, and must be unique:

   ```bash
   python3 tools/new_skill.py <skill-name> "Human title"
   ```

   This creates `skills/<skill-name>/` (`SKILL.md`, `README.md`, `LICENSE`) and `tests/<skill-name>/run.sh` from `templates/skill/`.

2. Write `SKILL.md`.
   - `name` equals the directory name. `description` starts with "Use when" and lists triggers; it does not summarize the workflow, because agents may follow the summary instead of reading the skill.
   - Keep it agent-neutral: refer to the skill's own location as `<skill-directory>`, and put agent-specific tools (Claude Code, Codex) in labelled subsections rather than in the shared workflow.
   - Keep it focused. Move detail that is needed only sometimes into `references/` and link to it.
   - Set `metadata.version` and bump it on every behavior change.

3. Add only resources the skill uses: `references/` for on-demand detail, `scripts/` for helpers, `assets/` for fixtures and templates, `agents/openai.yaml` for Codex UI metadata. A skill is installed without the rest of the repository, so it must be self-contained: no imports from other skills, tools or tests. Invoke helpers through their interpreter (`bash scripts/x.sh`, `python3 scripts/x.py`); installers may drop executable bits.

4. Write tests in `tests/<skill-name>/` with `run.sh` as the single entry point. It must be runnable from any directory, clean up after itself, and skip (exit 0 with a `SKIP:` line) checks that need a platform the runner lacks. Tests live outside the skill so they are not installed.

5. Write the skill's `README.md` for people: what it does, requirements, side effects (what it reads, writes and executes), limits, and how to run its tests.

6. Register it.
   - `.claude-plugin/marketplace.json`: add `./skills/<skill-name>` to the `skills` list of exactly one plugin, and bump that plugin's `version`. Plugins are domain groups (`apple-dev`, ...). Start a new group only for a new domain; give it `"source": "./"` and `"strict": false`.
   - `README.md`: add a row to the Skills table, including the plugin name.
   - `CHANGELOG.md`: add an entry.

7. Verify before submitting. CI runs the first command on macOS and Linux:

   ```bash
   bash tests/run-all.sh
   npx skills add . --list
   claude plugin validate .
   ```

   Also try the real workflow in an isolated project with a fresh agent session that has only the skill, including failure paths. Reading the instructions is not a substitute for watching an agent follow them.

## Changing a skill

Preserve its public commands and any files it writes into user projects unless the change documents a migration. Bump `metadata.version` and the containing plugin's `version`, add a `CHANGELOG.md` entry, and update the skill README and the root table when behavior or requirements change.

## Repository rules

- No root `SKILL.md`: it would shadow the individual skills.
- Do not commit generated output, app bundles, caches, secrets, real user data, developer-specific paths or machine-specific configuration. `artifacts/` is ignored for local output.
- Include only material you have the rights to, and keep required license notices. Each skill carries its own `LICENSE`.
- `tools/validate.py` enforces the structural rules above; `tools/` and `templates/` are never installed with a skill.

Format references: [Agent Skills specification](https://agentskills.io/specification), [skills CLI discovery](https://github.com/vercel-labs/skills/blob/main/docs/creating-skills.md).
