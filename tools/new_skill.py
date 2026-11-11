#!/usr/bin/env python3
"""Scaffold skills/<name>/ and tests/<name>/ from templates/skill/.

Usage: python3 tools/new_skill.py <skill-name> ["Human title"]
"""
import os
from pathlib import Path
import re
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    if len(sys.argv) not in (2, 3):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    name = sys.argv[1]
    if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', name) or len(name) > 64:
        print('new_skill: use lowercase letters, digits and single hyphens (max 64).', file=sys.stderr)
        return 2
    title = sys.argv[2] if len(sys.argv) == 3 else name.replace('-', ' ').capitalize()
    skill, tests = ROOT / 'skills' / name, ROOT / 'tests' / name
    if skill.exists() or tests.exists():
        print('new_skill: %s already exists.' % name, file=sys.stderr)
        return 2
    skill.mkdir(parents=True)
    tests.mkdir(parents=True)
    template = ROOT / 'templates' / 'skill'
    for source, target in (('SKILL.template.md', skill / 'SKILL.md'), ('README.template.md', skill / 'README.md'),
                           ('run.template.sh', tests / 'run.sh')):
        text = (template / source).read_text(encoding='utf-8')
        target.write_text(text.replace('{{name}}', name).replace('{{title}}', title), encoding='utf-8')
    os.chmod(tests / 'run.sh', 0o755)
    shutil.copyfile(ROOT / 'LICENSE', skill / 'LICENSE')
    print('Created skills/%s/ and tests/%s/run.sh. Next:' % (name, name))
    print('  1. Write skills/%s/SKILL.md and README.md; replace the failing stub in tests/%s/run.sh.' % (name, name))
    print('  2. Add ./skills/%s to a plugin in .claude-plugin/marketplace.json and bump that plugin version.' % name)
    print('  3. Add a row to the Skills table in README.md and an entry to CHANGELOG.md.')
    print('  4. Run tests/run-all.sh.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
