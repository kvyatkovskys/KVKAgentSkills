#!/usr/bin/env python3
"""Discover projects, save reviewed fixture paths, and dispatch preview helpers.

Discovery reads text only. Configuration records provenance, not a claim that an
agent's adaptation is faithful or that executable Swift is sandboxed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

CONFIG = '.swiftui-preview/config.json'
VERSION = 1
SKIP = {'.git', '.build', '.swiftpm', '.swiftui-preview', 'DerivedData',
        'node_modules', 'Pods', 'Carthage'}


class SetupError(ValueError):
    pass


def root_path(value):
    root = Path(value).expanduser().resolve(strict=True)
    if not root.is_dir():
        raise SetupError('Root must be an existing directory.')
    return root


def relative_path(root, value, kind):
    if not isinstance(value, str) or not value or '\\' in value:
        raise SetupError('Paths must be nonempty project-relative POSIX paths.')
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in ('', '.', '..') for part in value.split('/')):
        raise SetupError('Paths must be relative, without dot or parent traversal.')
    target = root.joinpath(*path.parts)
    # Reject symlinks even inside the root: saved paths must identify stable files.
    current = root
    for part in path.parts:
        current = current / part
        if current.is_symlink():
            raise SetupError('Selected paths and configuration cannot contain symlinks.')
    resolved = target.resolve(strict=True)
    if root not in resolved.parents:
        raise SetupError('Path escapes the project root.')
    if kind == 'swift':
        if not target.is_file() or target.suffix != '.swift':
            raise SetupError('Source and fixture must be existing .swift files.')
    elif kind == 'project':
        if not ((target.name == 'Package.swift' and target.is_file()) or
                (target.suffix in ('.xcodeproj', '.xcworkspace') and target.is_dir())):
            raise SetupError('Project must be Package.swift, .xcodeproj, or .xcworkspace.')
    return target


def text_file(path):
    return path.read_text(encoding='utf-8')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def evidence(text):
    signals = []
    for label, pattern in (
        ('UIKit import', r'^\s*(?:@\w+\s+)?import\s+UIKit\b'),
        ('iOS conditional', r'#if\s+os\(iOS\)'),
        ('macOS conditional', r'#if\s+os\(macOS\)'),
        ('macOS platform declaration', r'\.macOS\s*\('),
        ('iOS platform declaration', r'\.iOS\s*\('),
        ('iOS Xcode platform', r'\b(?:iphoneos|iphonesimulator)\b'),
        ('macOS Xcode platform', r'\bmacosx\b'),
    ):
        if re.search(pattern, text, re.MULTILINE):
            signals.append(label)
    return signals


def discover(root):
    projects, sources, skipped = [], [], []
    for base, dirs, files in os.walk(root, followlinks=False):
        base = Path(base)
        kept = []
        for name in sorted(dirs):
            path = base / name
            if path.is_symlink():
                skipped.append(path.relative_to(root).as_posix())
            elif name in SKIP:
                continue
            elif path.suffix in ('.xcodeproj', '.xcworkspace'):
                metadata = path / 'project.pbxproj'
                signals = evidence(text_file(metadata)) if metadata.is_file() and not metadata.is_symlink() else []
                projects.append({'path': path.relative_to(root).as_posix(),
                                 'kind': path.suffix[1:], 'platform_evidence': signals})
            else:
                kept.append(name)
        dirs[:] = kept
        for name in sorted(files):
            path = base / name
            if path.is_symlink():
                skipped.append(path.relative_to(root).as_posix())
                continue
            if path.suffix != '.swift':
                continue
            content = text_file(path)
            relative = path.relative_to(root).as_posix()
            if name == 'Package.swift':
                projects.append({'path': relative, 'kind': 'swiftpm',
                                 'platform_evidence': evidence(content)})
            elif re.search(r'^\s*import\s+SwiftUI\b|#Preview\b', content, re.MULTILINE):
                sources.append({'path': relative, 'has_preview': bool(re.search(r'#Preview\b', content)),
                                'platform_evidence': evidence(content),
                                'declared_views': re.findall(r'\bstruct\s+(\w+)\s*:\s*(?:SwiftUI\.)?View\b', content)})
    projects.sort(key=lambda item: item['path'])
    sources.sort(key=lambda item: item['path'])
    return {'schema_version': VERSION, 'projects': projects, 'sources': sources,
            'selection_required': {'project': len(projects) != 1, 'source': len(sources) != 1},
            'skipped_symlinks': sorted(skipped),
            'notes': ['Text evidence only; missing platform evidence is unknown, not unsupported.',
                      'Inspect the requested component and its previews before adapting a fixture.']}


def config_path(root):
    directory = root / '.swiftui-preview'
    path = root / CONFIG
    if directory.is_symlink() or path.is_symlink():
        raise SetupError('Configuration and its directory cannot be symlinks.')
    if directory.exists() and not directory.is_dir():
        raise SetupError('Configuration parent must be a directory.')
    if path.exists() and not path.is_file():
        raise SetupError('Configuration must be a regular file.')
    return path


def validate_config(root, config, check_hashes=True):
    keys = {'schema_version', 'project_marker', 'source', 'fixture', 'component', 'platform', 'provenance'}
    if not isinstance(config, dict) or set(config) != keys or type(config['schema_version']) is not int or config['schema_version'] != VERSION:
        raise SetupError('Unsupported or malformed configuration schema; configure again.')
    if config['platform'] != 'macos' or not isinstance(config['component'], str) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.]*', config['component']):
        raise SetupError('Configuration requires a component name and platform macos.')
    provenance = config['provenance']
    if not isinstance(provenance, dict) or set(provenance) != {'source_sha256', 'fixture_sha256'} or any(not isinstance(value, str) or not re.fullmatch(r'[0-9a-f]{64}', value) for value in provenance.values()):
        raise SetupError('Malformed source/fixture provenance.')
    relative_path(root, config['project_marker'], 'project')
    source = relative_path(root, config['source'], 'swift')
    fixture = relative_path(root, config['fixture'], 'swift')
    if source == fixture or source.samefile(fixture):
        raise SetupError('Fixture must be a separate adapted file, not the production source.')
    content = text_file(fixture)
    if re.search(r'@main\b|#Preview\b|^\s*import\s+UIKit\b', content, re.MULTILINE):
        raise SetupError('Fixture must omit @main, #Preview, and UIKit; use a Simulator/Canvas workflow for iOS-only code.')
    if not re.search(r'\b(?:enum|struct|class)\s+PreviewFixture\b', content) or not re.search(r'\bstatic\s+func\s+makeView\s*\(', content):
        raise SetupError('Fixture needs PreviewFixture.static makeView().')
    if check_hashes and (digest(source) != provenance['source_sha256'] or digest(fixture) != provenance['fixture_sha256']):
        raise SetupError('Source or fixture changed: inspect and readapt the genuine component, then configure --replace.')
    return fixture


def configure(root, args):
    source = relative_path(root, args.source, 'swift')
    fixture = relative_path(root, args.fixture, 'swift')
    config = {'schema_version': VERSION, 'project_marker': args.project,
              'source': args.source, 'fixture': args.fixture,
              'component': args.component, 'platform': 'macos',
              'provenance': {'source_sha256': digest(source), 'fixture_sha256': digest(fixture)}}
    validate_config(root, config)
    path = config_path(root)
    if path.exists() and not args.replace:
        raise SetupError('Configuration already exists; inspect it before configure --replace.')
    path.parent.mkdir(exist_ok=True)
    # Exclusive creation preserves existing work. Replacement is an explicit CLI action.
    with path.open('w' if args.replace else 'x', encoding='utf-8') as stream:
        json.dump(config, stream, indent=2, sort_keys=True)
        stream.write('\n')
    return {'config': CONFIG, 'component': args.component, 'platform': 'macos'}


def command(root, args):
    config = json.loads(config_path(root).read_text(encoding='utf-8'))
    fixture = validate_config(root, config)
    if args.mode != 'render' and (args.theme is not None or args.frame):
        raise SetupError('--theme and --frame apply only to render; gallery includes all variants and live has native controls.')
    output = Path(args.output).expanduser()
    if not output.is_absolute():
        output = root / output
    if output.is_symlink() or output.exists():
        raise SetupError('Choose a new output path; bootstrap never overwrites artifacts.')
    if not output.parent.is_dir():
        raise SetupError('Output parent must already exist.')
    output = output.parent.resolve() / output.name
    suffix = {'render': '.png', 'gallery': '.html', 'live': '.app'}[args.mode]
    if output.suffix.lower() != suffix:
        raise SetupError('Output extension must be ' + suffix + '.')
    scripts = Path(__file__).resolve().parent
    argv = ['/bin/bash', str(scripts / (args.mode + '.sh')), str(fixture), str(output), str(args.width), str(args.height)]
    if args.mode == 'render':
        argv += [args.theme or 'light', args.locale]
        if args.frame:
            argv.append('--frame')
    else:
        argv += [args.locale]
        if args.mode == 'gallery':
            argv.append(config['component'])
    return argv


def dimension(value):
    if not re.fullmatch(r'[1-9][0-9]{0,3}', value) or int(value) > 4096:
        raise argparse.ArgumentTypeError('Dimensions must be integers from 1 to 4096.')
    return int(value)


def locale(value):
    if len(value) > 128 or not re.fullmatch(r'[A-Za-z][A-Za-z0-9_@=.\-]*', value):
        raise argparse.ArgumentTypeError('Supply a locale identifier such as en_US.')
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    discover_parser = sub.add_parser('discover', help='Read-only text discovery; never evaluates manifests or builds.')
    configure_parser = sub.add_parser('configure', aliases=['init'], help='Save paths after an agent prepares and reviews a genuine fixture.')
    run_parser = sub.add_parser('run', help='Validate saved provenance and invoke one known helper; live builds only.')
    for child in (discover_parser, configure_parser, run_parser):
        child.add_argument('--root', required=True)
    for name in ('project', 'source', 'fixture', 'component'):
        configure_parser.add_argument('--' + name, required=True)
    configure_parser.add_argument('--replace', action='store_true', help='Explicitly replace an inspected existing configuration after adaptation.')
    run_parser.add_argument('--mode', choices=('render', 'gallery', 'live'), required=True)
    run_parser.add_argument('--output', required=True)
    run_parser.add_argument('--width', type=dimension, default=480)
    run_parser.add_argument('--height', type=dimension, default=320)
    run_parser.add_argument('--locale', type=locale, default='en_US')
    run_parser.add_argument('--theme', choices=('light', 'dark'))
    run_parser.add_argument('--frame', action='store_true')
    args = parser.parse_args()
    try:
        root = root_path(args.root)
        if args.action == 'discover':
            result = discover(root)
        elif args.action in ('configure', 'init'):
            result = configure(root, args)
        else:
            return subprocess.run(command(root, args), check=False).returncode
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except (SetupError, OSError, UnicodeError, json.JSONDecodeError) as error:
        print('bootstrap: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
