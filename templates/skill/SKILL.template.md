---
name: {{name}}
description: Use when TODO - state the situations, symptoms and words that should trigger this skill. Do not summarize the workflow here.
license: MIT
metadata:
  version: "0.1.0"
---

# {{title}}

TODO: one or two sentences on what this produces and its core principle. State requirements (OS, toolchain, runtimes).

`<skill-directory>` below is the directory containing this `SKILL.md`. Claude Code states it as the skill's base directory when the skill loads; in other agents use the path this file was read from.

## When not to use

TODO: adjacent tasks this skill does not cover, and what to do instead.

## Workflow

TODO: numbered steps. Invoke bundled helpers through their interpreter, for example:

```bash
python3 "<skill-directory>/scripts/tool.py" --help
```

## Present the result

TODO: what to show the user and what counts as verified. Put agent-specific tools under **Claude Code.** / **Codex.** labels.

## Common mistakes

TODO: what goes wrong and the fix.
