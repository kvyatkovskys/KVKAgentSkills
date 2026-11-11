#!/usr/bin/env python3
"""Rebuild-in-place regression test for bootstrap refresh; builds but never launches."""
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

SCRIPT = Path(__file__).resolve().parents[2] / 'skills' / 'swiftui-component-preview' / 'scripts' / 'bootstrap.py'
SOURCE = 'import SwiftUI\nstruct Counter: View {\n    @State private var count = 0\n    var body: some View { Button("Count \\(count)") { count += 1 }.padding() }\n}\n'
FIXTURE = SOURCE + '@MainActor enum PreviewFixture { static func makeView() -> some View { Counter() } }\n'


def cli(root, *args):
    return subprocess.run([sys.executable, str(SCRIPT), args[0], '--root', str(root), *args[1:]], capture_output=True, text=True)


def identifier(app):
    return plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleIdentifier']


def main():
    if sys.platform != 'darwin':
        print('SKIP: live preview builds require macOS.')
        return
    with tempfile.TemporaryDirectory(prefix='preview refresh test ') as temp:
        root = Path(temp).resolve()
        (root / 'Package.swift').write_text('// swift-tools-version: 6.0\n')
        (root / 'Counter.swift').write_text(SOURCE)
        fixture = root / 'Fixture.swift'
        fixture.write_text(FIXTURE)
        app = root / 'Counter Preview.app'
        refresh = ('refresh', '--output', 'Counter Preview.app', '--width', '520', '--height', '200', '--no-launch')
        assert cli(root, *refresh).returncode != 0, 'refresh must require configuration'
        assert cli(root, 'configure', '--project', 'Package.swift', '--source', 'Counter.swift', '--fixture', 'Fixture.swift', '--component', 'Counter', '--platform', 'macos').returncode == 0
        first = cli(root, *refresh)
        assert first.returncode == 0, first.stderr
        assert json.loads(first.stdout) ["launched"] is False
        original = identifier(app)

        # Stale fixture: run refuses, refresh records the new hash and replaces the app in place.
        fixture.write_text(FIXTURE.replace('Count ', 'Total '))
        assert cli(root, 'run', '--mode', 'live', '--output', 'Other.app').returncode != 0
        second = cli(root, *refresh)
        assert second.returncode == 0, second.stderr
        assert identifier(app) != original, 'app was not rebuilt'
        assert cli(root, 'run', '--mode', 'render', '--output', 'after.png', '--width', '200', '--height', '80').returncode == 0, 'hashes were not recorded'

        # A failed build keeps the previous app and configuration.
        rebuilt, saved = identifier(app), (root / '.swiftui-preview/config.json').read_text()
        fixture.write_text(FIXTURE + 'this is not swift\n')
        failed = cli(root, *refresh)
        assert failed.returncode != 0 and 'unchanged' in failed.stderr, failed.stderr
        assert identifier(app) == rebuilt and (root / '.swiftui-preview/config.json').read_text() == saved
        assert not [item for item in root.iterdir() if item.name.startswith('.refresh-')], 'staging left behind'
        fixture.write_text(FIXTURE)

        # Never replace something this skill did not build.
        foreign = root / 'Foreign.app'
        (foreign / 'Contents').mkdir(parents=True)
        (foreign / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'com.example.real', 'CFBundleExecutable': 'Real'}))
        refused = cli(root, 'refresh', '--output', 'Foreign.app', '--no-launch')
        assert refused.returncode != 0 and 'Refusing' in refused.stderr, refused.stderr
        assert identifier(foreign) == 'com.example.real'
        (root / 'file.app').write_text('keep')
        assert cli(root, 'refresh', '--output', 'file.app', '--no-launch').returncode != 0
        assert (root / 'file.app').read_text() == 'keep'
        assert cli(root, 'refresh', '--output', 'x.app', '--width', 'fit', '--no-launch').returncode != 0
        print('PASS: refresh rebuilds in place, records hashes, preserves state on failed builds, and refuses foreign outputs; app not launched')


if __name__ == '__main__':
    main()
