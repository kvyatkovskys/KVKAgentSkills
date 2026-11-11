#!/usr/bin/env python3
"""Portable bootstrap regression tests; no Swift toolchain needed."""
import json
import argparse
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tempfile
import unittest

BOOTSTRAP = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'scripts' / 'bootstrap.py'))

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts' / 'bootstrap.py'
SOURCE = 'import SwiftUI\nstruct StatusCard: View { var body: some View { Text("Ready") } }\n#Preview { StatusCard() }\n'
FIXTURE = 'import SwiftUI\nstruct StatusCard: View { var body: some View { Text("Ready") } }\n@MainActor enum PreviewFixture { static func makeView() -> some View { StatusCard() } }\n'

class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='preview bootstrap tests ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve() / 'Project with spaces'
        self.root.mkdir()
        (self.root / 'Package.swift').write_text('// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: "Demo", platforms: [.macOS(.v14)])\n')
        (self.root / 'StatusCard.swift').write_text(SOURCE)
        (self.root / 'Fixtures').mkdir()
        (self.root / 'Fixtures' / 'Card.swift').write_text(FIXTURE)

    def cli(self, *args, ok=True, root=None):
        result = subprocess.run([sys.executable, str(SCRIPT), args[0], '--root', str(root or self.root), *args[1:]], capture_output=True, text=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def configure(self, *args, **kwargs):
        return self.cli('configure', '--project', 'Package.swift', '--source', 'StatusCard.swift', '--fixture', 'Fixtures/Card.swift', '--component', 'StatusCard', *args, **kwargs)

    def test_discover_without_executing_manifest(self):
        sentinel = Path(self.temp.name) / 'executed'
        (self.root / 'Package.swift').write_text('import Foundation\ntry! "executed".write(toFile: "' + str(sentinel) + '", atomically: true, encoding: .utf8)\n')
        result = json.loads(self.cli('discover').stdout)
        self.assertEqual(result['projects'][0]['path'], 'Package.swift')
        source = next(item for item in result['sources'] if item['path'] == 'StatusCard.swift')
        self.assertTrue(source['has_preview'])
        self.assertFalse(sentinel.exists())
        self.assertFalse((self.root / '.swiftui-preview').exists())

    def test_configuration_is_relative_and_cannot_overwrite(self):
        self.configure()
        config = json.loads((self.root / '.swiftui-preview/config.json').read_text())
        self.assertEqual(config['source'], 'StatusCard.swift')
        self.assertNotIn(str(self.root), json.dumps(config))
        self.configure(ok=False)

    def test_project_ambiguity_and_platform_evidence(self):
        (self.root / 'Mobile.xcodeproj').mkdir()
        (self.root / 'Mobile.xcodeproj/project.pbxproj').write_text('SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";')
        (self.root / 'Desktop.xcworkspace').mkdir()
        (self.root / 'Phone.swift').write_text('import SwiftUI\nimport UIKit\nstruct Phone: View { var body: some View { Text("Phone") } }')
        result = json.loads(self.cli('discover').stdout)
        self.assertTrue(result['selection_required']['project'])
        self.assertEqual(len(result['projects']), 3)
        phone = next(item for item in result['sources'] if item['path'] == 'Phone.swift')
        self.assertIn('UIKit import', phone['platform_evidence'])
        workspace = next(item for item in result['projects'] if item['kind'] == 'xcworkspace')
        self.assertEqual(workspace['platform_evidence'], [])

    def test_xcode_without_swiftpm(self):
        (self.root / 'Package.swift').unlink()
        (self.root / 'Desktop.xcodeproj').mkdir()
        self.cli('init', '--project', 'Desktop.xcodeproj', '--source', 'StatusCard.swift', '--fixture', 'Fixtures/Card.swift', '--component', 'StatusCard')

    def test_traversal_absolute_and_missing_paths(self):
        for value in ('../StatusCard.swift', str(self.root / 'StatusCard.swift'), './StatusCard.swift', 'Absent.swift', 'Fixtures'):
            self.cli('configure', '--project', 'Package.swift', '--source', value, '--fixture', 'Fixtures/Card.swift', '--component', 'StatusCard', ok=False)
        self.assertFalse((self.root / '.swiftui-preview').exists())

    def test_symlink_paths_and_configuration_rejected(self):
        (self.root / 'Link.swift').symlink_to(self.root / 'StatusCard.swift')
        self.cli('configure', '--project', 'Package.swift', '--source', 'Link.swift', '--fixture', 'Fixtures/Card.swift', '--component', 'StatusCard', ok=False)
        outside = Path(self.temp.name) / 'outside'
        outside.mkdir()
        (outside / 'Escaped.swift').write_text(SOURCE)
        (self.root / 'Outside.swift').symlink_to(outside / 'Escaped.swift')
        self.cli('configure', '--project', 'Package.swift', '--source', 'Outside.swift', '--fixture', 'Fixtures/Card.swift', '--component', 'StatusCard', ok=False)
        (self.root / '.swiftui-preview').symlink_to(outside, target_is_directory=True)
        self.configure(ok=False)
        self.assertEqual([item.name for item in outside.iterdir()], ['Escaped.swift'])
        result = json.loads(self.cli('discover').stdout)
        self.assertIn('Link.swift', result['skipped_symlinks'])

    def test_config_file_symlink_and_directory_rejected(self):
        self.configure()
        path = self.root / '.swiftui-preview/config.json'
        content = path.read_text()
        path.unlink()
        outside = Path(self.temp.name) / 'outside.json'
        outside.write_text(content)
        path.symlink_to(outside)
        self.configure('--replace', ok=False)
        self.assertEqual(outside.read_text(), content)
        path.unlink()
        path.mkdir()
        self.configure('--replace', ok=False)

    def run_args(self, **kwargs):
        values = dict(mode='render', output='render.png', width=480, height=320, locale='en_US', theme=None, frame=False)
        values.update(kwargs)
        return argparse.Namespace(**values)

    def test_relocation_and_stale_source_or_fixture(self):
        self.configure()
        moved = Path(self.temp.name).resolve() / 'Relocated'
        shutil.copytree(self.root, moved)
        argv = BOOTSTRAP['command'](moved, self.run_args())
        self.assertEqual(argv[2], str(moved / 'Fixtures/Card.swift'))
        for selected in ('StatusCard.swift', 'Fixtures/Card.swift'):
            path = self.root / selected
            original = path.read_text()
            path.write_text(original + '\n// changed\n')
            result = self.cli('run', '--mode', 'render', '--output', 'x.png', ok=False)
            self.assertIn('readapt', result.stderr)
            path.write_text(original)
        self.configure('--replace')

    def test_malformed_schema_and_missing_fields(self):
        self.configure()
        path = self.root / '.swiftui-preview/config.json'
        original = json.loads(path.read_text())
        bad = [None, [], {}, {'schema_version': 999}, dict(original, schema_version=True), dict(original, source=5), dict(original, provenance={}), dict(original, platform='ios')]
        for value in bad:
            path.write_text(json.dumps(value))
            self.cli('run', '--mode', 'render', '--output', 'x.png', ok=False)
        path.write_text('{')
        self.cli('run', '--mode', 'render', '--output', 'x.png', ok=False)

    def test_fixture_contract(self):
        fixture = self.root / 'Fixtures/Card.swift'
        for content in ('import SwiftUI\n', FIXTURE + '\n@main struct App {}', FIXTURE + '\n#Preview { StatusCard() }', FIXTURE + '\nimport UIKit'):
            fixture.write_text(content)
            self.configure(ok=False)
        self.cli('configure', '--project', 'Package.swift', '--source', 'StatusCard.swift', '--fixture', 'StatusCard.swift', '--component', 'StatusCard', ok=False)

    def test_dispatch_all_modes_and_safe_argv(self):
        self.configure()
        for mode, suffix in (('render', 'png'), ('gallery', 'html'), ('live', 'app')):
            argv = BOOTSTRAP['command'](self.root, self.run_args(mode=mode, output='Result .' + suffix))
            self.assertEqual(argv[:2], ['/bin/bash', str(SCRIPT.parent / (mode + '.sh'))])
            self.assertEqual(argv[2], str(self.root / 'Fixtures/Card.swift'))
            self.assertEqual(argv[3], str(self.root / ('Result .' + suffix)))
        # Exercise dispatch in a private helper copy: shell syntax stays one literal arg.
        helper = Path(self.temp.name) / 'Helper copy'
        helper.mkdir()
        shutil.copy2(SCRIPT, helper / 'bootstrap.py')
        (helper / 'render.sh').write_text('printf "%s\\0" "$@" > "$PREVIEW_ARGS"\n')
        captured = Path(self.temp.name) / 'argv'
        marker = self.root / 'injected'
        output = str(self.root / "$(touch injected); 'quoted'.png")
        result = subprocess.run([sys.executable, str(helper / 'bootstrap.py'), 'run', '--root', str(self.root), '--mode', 'render', '--output', output], cwd=self.root, env=dict(os.environ, PREVIEW_ARGS=str(captured)), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(captured.read_bytes().split(b'\0')[1].decode(), output)
        self.assertFalse(marker.exists())

    def test_invalid_output_and_options(self):
        self.configure()
        (self.root / 'x.png').write_text('keep')
        self.cli('run', '--mode', 'render', '--output', 'x.png', ok=False)
        self.assertEqual((self.root / 'x.png').read_text(), 'keep')
        (self.root / 'linked.png').symlink_to(self.root / 'x.png')
        for extra in (['--output', 'linked.png'], ['--output', 'missing/x.png'], ['--output', 'x.html'], ['--output', 'new.png', '--width', '4097'], ['--output', 'new.png', '--locale', 'en_US;touch x']):
            self.cli('run', '--mode', 'render', *extra, ok=False)
        self.cli('run', '--mode', 'live', '--output', 'New.app', '--frame', ok=False)

if __name__ == '__main__':
    unittest.main()
