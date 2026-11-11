# Adding a skill

1. Create `skills/<lowercase-hyphenated-name>/` with a unique name.
2. Add `SKILL.md` with YAML frontmatter containing `name` and `description`. The name must match the directory. Explain when the skill applies and keep the instructions focused.
3. Include only resources that the skill uses. Optional directories are `agents/` for UI metadata, `scripts/` for helpers, `assets/` for fixtures/templates, and `tests/` for executable checks. Make each skill self-contained; another skill should not be required just to run its helpers.
4. Document toolchain requirements, supported platforms, side effects and known limits. Keep project-specific code, credentials, real user data and developer-specific paths out of the package. Obtain rights to included material and retain required license notices.
5. Add the skill to the root README catalog and describe installation with `--skill <name>`.
6. Test its real workflow in an isolated project, including relevant failure paths. Run the skill's documented tests and verify discovery before submitting:

```bash
npx skills add . --list
```

Follow the [Agent Skills format](https://agentskills.io/specification) and [skills discovery conventions](https://github.com/vercel-labs/skills/blob/main/docs/creating-skills.md). Do not add a root `SKILL.md`: this repository contains multiple independently selectable skills. Do not commit generated renders, app bundles, caches, secrets or machine-specific project configurations.

Existing skill changes should preserve its public CLI and user edits unless the change explicitly documents a migration. Update its README and root catalog when its behavior or requirements change.
