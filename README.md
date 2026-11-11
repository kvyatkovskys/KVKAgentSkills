# KVKAgentSkills

A growing collection of reusable skills for coding agents. Each skill is self-contained and independently installable through the [skills CLI](https://github.com/vercel-labs/skills).

## Install

Requires Node.js 22.20 or later for the installer. Run from your project:

```bash
npx skills add kvyatkovskys/KVKAgentSkills
```

Select the skills and agents you want. To install only SwiftUI Component Preview for Codex:

```bash
npx skills add kvyatkovskys/KVKAgentSkills --skill swiftui-component-preview --agent codex
```

Add `--global` to make the selected skill available across your projects:

```bash
npx skills add kvyatkovskys/KVKAgentSkills --skill swiftui-component-preview --agent codex --global
```

List available skills without installing:

```bash
npx skills add kvyatkovskys/KVKAgentSkills --list
```

The installer supports other coding agents; each skill documents its own runtime requirements. Installing instructions does not install Xcode or other toolchains.

## Skills

| Skill | Purpose | Requirements |
| --- | --- | --- |
| [swiftui-component-preview](skills/swiftui-component-preview) | First-call project discovery and adaptation, SwiftUI PNG renders, interactive theme gallery, and a live native preview window. | macOS 14+, Xcode/Swift 6; Python 3.8+ for project setup, gallery and live builds. |

After installation, ask Codex:

```text
$swiftui-component-preview Show a preview of SettingsView in this project.
```

On first use the skill inspects the project and adapts the real component into a project-local fixture. It saves relative-path configuration in `.swiftui-preview` for subsequent calls. UIKit-only screens and complex project dependencies need a compatible simulator or project-specific workflow; see the skill instructions. Trusted fixtures execute Swift with ordinary user permissions.

## Repository layout

```text
KVKAgentSkills/
├── README.md
├── CONTRIBUTING.md
├── LICENSE
└── skills/
    ├── swiftui-component-preview/
    │   ├── SKILL.md
    │   ├── agents/openai.yaml
    │   ├── assets/
    │   ├── scripts/
    │   └── tests/
    └── <future-skill>/
        └── SKILL.md
```

Every new skill gets its own `skills/<name>/` directory. The root stays a collection catalog; there is no root `SKILL.md` to shadow individual skills. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE). Individual skill directories retain their license notices.
