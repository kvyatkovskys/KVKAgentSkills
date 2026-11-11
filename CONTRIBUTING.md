# Adding a skill

1. Create `skills/<lowercase-hyphenated-name>/` with a unique name.
2. Add `SKILL.md` with YAML frontmatter containing `name` and `description`. The name must match the directory. Explain when the skill applies and keep the instructions focused.
3. Include only resources that the skill uses. Optional directories are `agents/` for UI metadata, `references/` for detail that `SKILL.md` links to and agents load on demand, `scripts/` for helpers, and `assets/` for fixtures/templates. Put executable checks in `tests/<name>/` at the repository root so they are not installed with the skill. Make each skill self-contained; another skill should not be required just to run its helpers.
4. Document toolchain requirements, supported platforms, side effects and known limits. Keep project-specific code, credentials, real user data and developer-specific paths out of the package. Obtain rights to included material and retain required license notices.
5. Add the skill to the root README catalog and describe installation with `--skill <name>`. Skills under `skills/` are picked up by the Claude Code plugin automatically; bump `version` in `.claude-plugin/plugin.json` so installed plugins update.
6. Keep `SKILL.md` agent-neutral. Start the description with when to use the skill, refer to the skill's own location as `<skill-directory>`, and put agent-specific tools (Claude Code, Codex) in clearly labelled subsections rather than in the shared workflow.
7. Test its real workflow in an isolated project, including relevant failure paths. Run the skill's documented tests and verify discovery before submitting:

```bash
npx skills add . --list
claude plugin validate .
```

Follow the [Agent Skills format](https://agentskills.io/specification) and [skills discovery conventions](https://github.com/vercel-labs/skills/blob/main/docs/creating-skills.md). Do not add a root `SKILL.md`: this repository contains multiple independently selectable skills. Do not commit generated renders, app bundles, caches, secrets or machine-specific project configurations.

Existing skill changes should preserve its public CLI and user edits unless the change explicitly documents a migration. Update its README and root catalog when its behavior or requirements change.
