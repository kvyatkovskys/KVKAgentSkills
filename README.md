# KVKAgentSkills

A growing collection of reusable skills for coding agents. Each skill is self-contained and independently installable through the [skills CLI](https://github.com/vercel-labs/skills).

## Install

Requires Node.js 22.20 or later for the installer. Run from your project:

```bash
npx skills add kvyatkovskys/KVKAgentSkills
```

Select the skills and agents you want. To install only SwiftUI Component Preview for one agent:

```bash
npx skills add kvyatkovskys/KVKAgentSkills --skill swiftui-component-preview --agent claude-code
```

```bash
npx skills add kvyatkovskys/KVKAgentSkills --skill swiftui-component-preview --agent codex
```

Add `--global` to make the selected skill available across your projects (`~/.claude/skills/` for Claude Code):

```bash
npx skills add kvyatkovskys/KVKAgentSkills --skill swiftui-component-preview --agent claude-code --global
```

### Claude Code plugin

The repository is also a Claude Code plugin marketplace. Inside Claude Code:

```text
/plugin marketplace add kvyatkovskys/KVKAgentSkills
/plugin install kvk-agent-skills@kvk-agent-skills
```

The plugin installs every skill in the collection and updates with `/plugin marketplace update kvk-agent-skills`. Plugin skills are namespaced: `/kvk-agent-skills:swiftui-component-preview`.

List available skills without installing:

```bash
npx skills add kvyatkovskys/KVKAgentSkills --list
```

The installer supports other coding agents; each skill documents its own runtime requirements. Installing instructions does not install Xcode or other toolchains.

## Skills

| Skill | Purpose | Requirements |
| --- | --- | --- |
| [swiftui-component-preview](skills/swiftui-component-preview) | First-call project discovery and adaptation, SwiftUI PNG renders, interactive theme gallery, and a live native preview window. | macOS 14+, Xcode 15+ (Swift 5.9+); Python 3.8+ for project setup, gallery and live builds. |

After installation, start a new session and ask your agent. In Claude Code:

```text
/swiftui-component-preview Show a preview of SettingsView in this project.
```

In Codex:

```text
$swiftui-component-preview Show a preview of SettingsView in this project.
```

Both agents also pick the skill up from a plain request such as "show me a preview of SettingsView".

Name the output to choose it: `png`, `gallery`, or `live`, as in `/swiftui-component-preview live SettingsView`. Without one the agent infers it from the request (looks → PNG, comparing themes → gallery, clicking through → live window) and defaults to a PNG for a single component; for a whole screen with no hint it asks which output you want.

On first use the skill inspects the project and adapts the real component into a project-local fixture. It saves relative-path configuration in `.swiftui-preview` for subsequent calls. UIKit-only screens and complex project dependencies need a compatible simulator or project-specific workflow; see the skill instructions. Trusted fixtures execute Swift with ordinary user permissions.

## Repository layout

```text
KVKAgentSkills/
├── README.md
├── CONTRIBUTING.md
├── LICENSE
├── .claude-plugin/        # Claude Code plugin + marketplace manifests
└── skills/
    ├── swiftui-component-preview/
    │   ├── SKILL.md
    │   ├── agents/openai.yaml
    │   ├── assets/
    │   ├── references/
    │   └── scripts/
    └── <future-skill>/
        └── SKILL.md
tests/
└── swiftui-component-preview/   # not shipped with the skill
```

Every new skill gets its own `skills/<name>/` directory. The root stays a collection catalog; there is no root `SKILL.md` to shadow individual skills. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE). Individual skill directories retain their license notices.
