#!/usr/bin/env python3
"""Repository-wide checks that keep every skill discoverable and catalogued.

No third-party packages. Exits non-zero and lists every problem found.
"""
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
NAME = re.compile(r'[a-z0-9]+(?:-[a-z0-9]+)*')


def frontmatter(text):
    """Top-level scalar keys of the leading YAML block; enough for name/description."""
    if not text.startswith('---\n'):
        return None
    end = text.find('\n---', 4)
    if end < 0:
        return None
    fields = {}
    for line in text[4:end].splitlines():
        match = re.match(r'([A-Za-z][\w-]*):\s*(.*)$', line)
        if match:
            fields[match.group(1)] = match.group(2).strip().strip('"\'')
    return fields


def main():
    problems = []
    skills = sorted(path.name for path in (ROOT / 'skills').iterdir() if path.is_dir())
    if (ROOT / 'SKILL.md').exists():
        problems.append('Root SKILL.md would shadow the individual skills; remove it.')
    readme = (ROOT / 'README.md').read_text(encoding='utf-8')
    changelog = (ROOT / 'CHANGELOG.md').read_text(encoding='utf-8') if (ROOT / 'CHANGELOG.md').exists() else ''

    for skill in skills:
        directory = ROOT / 'skills' / skill
        where = 'skills/' + skill
        if not NAME.fullmatch(skill) or len(skill) > 64:
            problems.append(where + ': directory name must be lowercase letters, digits and single hyphens, at most 64 characters.')
        manifest = directory / 'SKILL.md'
        if not manifest.is_file():
            problems.append(where + ': missing SKILL.md.')
            continue
        text = manifest.read_text(encoding='utf-8')
        fields = frontmatter(text)
        if fields is None:
            problems.append(where + '/SKILL.md: missing YAML frontmatter.')
            continue
        if fields.get('name') != skill:
            problems.append(where + '/SKILL.md: name %r must equal the directory name.' % fields.get('name'))
        description = fields.get('description', '')
        if not description:
            problems.append(where + '/SKILL.md: description is required.')
        elif len(description) > 1024:
            problems.append(where + '/SKILL.md: description is %d characters; the limit is 1024.' % len(description))
        elif not description.lower().startswith('use when'):
            problems.append(where + '/SKILL.md: description should start with "Use when" and state triggers, not the workflow.')
        if not re.search(r'^\s+version:\s*"?\d+\.\d+\.\d+"?\s*$', text[:text.find('\n---', 4)], re.MULTILINE):
            problems.append(where + '/SKILL.md: add metadata.version (for example "0.1.0") to the frontmatter.')
        if len(text.split()) > 5000:
            problems.append(where + '/SKILL.md: over 5000 words; move detail into references/.')
        for link in re.findall(r'\]\((?!https?://|#|mailto:|/)([^)\s]+)\)', text):
            if not (directory / link.split('#')[0]).exists():
                problems.append(where + '/SKILL.md: link to missing file %s.' % link)
        for required in ('README.md', 'LICENSE'):
            if not (directory / required).is_file():
                problems.append(where + ': missing %s; a skill is installed without the rest of the repository.' % required)
        if not (ROOT / 'tests' / skill / 'run.sh').is_file():
            problems.append('tests/%s/run.sh is missing; every skill needs one test entry point.' % skill)
        if (directory / 'tests').exists():
            problems.append(where + '/tests: keep tests in tests/%s/ so they are not installed.' % skill)
        if '](skills/%s)' % skill not in readme:
            problems.append('README.md: add %s to the Skills table.' % skill)
        if changelog and skill not in changelog:
            problems.append('CHANGELOG.md: no entry mentions %s.' % skill)

    try:
        marketplace = json.loads((ROOT / '.claude-plugin/marketplace.json').read_text(encoding='utf-8'))
    except (OSError, ValueError) as error:
        problems.append('.claude-plugin/marketplace.json: %s' % error)
        marketplace = {'plugins': []}
    listed, names = {}, set()
    for plugin in marketplace.get('plugins', []):
        name = plugin.get('name', '?')
        if name in names:
            problems.append('marketplace.json: duplicate plugin %s.' % name)
        names.add(name)
        if '`%s`' % name not in readme:
            problems.append('README.md: Skills table does not mention plugin `%s`.' % name)
        for entry in plugin.get('skills', []):
            path = (ROOT / entry).resolve()
            if not (path / 'SKILL.md').is_file():
                problems.append('marketplace.json: plugin %s lists %s, which is not a skill.' % (name, entry))
            listed.setdefault(path.name, []).append(name)
    for skill in skills:
        if skill not in listed:
            problems.append('marketplace.json: %s is not in any plugin; add ./skills/%s to one.' % (skill, skill))
        elif len(listed[skill]) > 1:
            problems.append('marketplace.json: %s is in several plugins (%s); pick one.' % (skill, ', '.join(listed[skill])))

    for problem in problems:
        print('validate: ' + problem, file=sys.stderr)
    if problems:
        return 1
    print('validate: %d skill(s), %d plugin(s) OK' % (len(skills), len(names)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
