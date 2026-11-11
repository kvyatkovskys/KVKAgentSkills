# KVKAgentSkills

A growing collection of reusable skills for coding agents. Each skill is self-contained, follows the [Agent Skills format](https://agentskills.io/specification), and installs on its own.

## Skills

| Skill | Purpose | Requirements | Claude Code plugin |
| --- | --- | --- | --- |
| [swiftui-component-preview](skills/swiftui-component-preview) | Preview a SwiftUI component for macOS, iOS, or iPadOS as PNG renders, an HTML theme gallery, or a live preview (native window or iOS Simulator), from a fixture adapted from the real component. | macOS 14+, Xcode 15+, Python 3.8+; iOS previews need an iOS 17+ simulator | `apple-dev` |

Each skill's own README covers usage, requirements, limits, and side effects. Installing a skill does not install its toolchain.

## Install

### Any agent: skills CLI

Requires Node.js 22.20 or later. Run from your project and pick skills and agents interactively:

```bash
npx skills add kvyatkovskys/KVKAgentSkills
```

Or name them. `<agent>` is `claude-code`, `codex`, or another agent the CLI supports; add `--global` to install for all your projects:

```bash
npx skills add kvyatkovskys/KVKAgentSkills --skill <skill-name> --agent <agent>
```

List what is available without installing:

```bash
npx skills add kvyatkovskys/KVKAgentSkills --list
```

### Claude Code: plugin marketplace

The repository is also a Claude Code plugin marketplace. Skills are grouped into plugins by domain (the last column of the table), so you install only the groups you need:

```text
/plugin marketplace add kvyatkovskys/KVKAgentSkills
/plugin install <plugin>@kvk-agent-skills
```

For example, the Apple platform group in one step:

```text
/plugin install apple-dev --marketplace kvyatkovskys/KVKAgentSkills
```

Update with `/plugin marketplace update kvk-agent-skills`. Plugin skills are namespaced as `/<plugin>:<skill-name>`.

### Manual

Copy `skills/<skill-name>/` into your agent's skills directory, for example `~/.claude/skills/` or `${CODEX_HOME:-$HOME/.codex}/skills/`.

## Use

Start a new session after installing. Invoke a skill by name, `/<skill-name>` in Claude Code or `$<skill-name>` in Codex, or just describe the task; agents pick skills up from their descriptions.

## Compatibility

Skills here use only the open Agent Skills format, so any agent that loads `SKILL.md` can install them. What differs is what each skill needs from the agent at run time; check the skill's requirements against the last three columns.

| Agent | Status | Runs local shell | Reads images | Can open GUI windows |
| --- | --- | --- | --- | --- |
| Claude Code | Tested | Yes | Yes | Yes |
| Codex CLI | Tested | Yes | Yes | Yes, outside a restricted sandbox |
| Cursor | Expected, not yet verified | Yes | Yes | Yes |
| GitHub Copilot (VS Code agent mode, Copilot CLI) | Expected, not yet verified | Yes | Yes | Yes |
| Gemini CLI | Expected, not yet verified | Yes | Yes | Yes |
| OpenCode | Expected, not yet verified | Yes | Depends on the model | Yes |
| Windsurf, Amp, Goose, Roo Code, Kiro, Junie | Expected, not yet verified | Yes | Depends on the model | Yes |
| Cloud agents on Linux runners (Codex cloud, Copilot coding agent, Jules) | Format loads; macOS-only skills cannot run | Remote only | Varies | No |

"Tested" means the skills are exercised in that agent before a release. "Expected" means the agent loads the same format and nothing in the skills is specific to another agent, but nobody has confirmed a full run; reports are welcome.

Agent-specific extras are optional and ignored elsewhere: `argument-hint` in the frontmatter and `.claude-plugin/marketplace.json` are for Claude Code, `agents/openai.yaml` is for Codex.

For `swiftui-component-preview` specifically: every output needs a local macOS shell with Xcode. Without image input the agent can still produce PNGs and the gallery but cannot inspect them itself. The live window needs a GUI session, so it does not work over SSH or in a sandbox that blocks launching apps. iOS and iPadOS outputs also need a full Xcode with an iOS Simulator runtime and permission to run `simctl`.

## Repository layout

```text
KVKAgentSkills/
├── .claude-plugin/marketplace.json   # Claude Code plugins: which skills each group contains
├── .github/workflows/ci.yml          # validation and tests
├── skills/
│   └── <skill-name>/                 # everything installed with the skill
│       ├── SKILL.md
│       ├── README.md
│       ├── LICENSE
│       ├── agents/openai.yaml        # optional Codex UI metadata
│       ├── references/               # optional, loaded on demand
│       ├── scripts/                  # optional helpers
│       └── assets/                   # optional fixtures and templates
├── tests/
│   ├── run-all.sh
│   └── <skill-name>/run.sh           # not installed with the skill
├── docs/images/<skill-name>/          # README screenshots, not installed
├── templates/skill/                  # starting point for a new skill
├── tools/                            # new_skill.py, validate.py
├── CHANGELOG.md
└── CONTRIBUTING.md
```

There is no root `SKILL.md`, so the collection never shadows an individual skill. To add a skill see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE). Each skill directory carries its own license notice.
