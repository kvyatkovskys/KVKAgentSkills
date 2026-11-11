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
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import time
import uuid

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


FORBIDDEN = (('@main', r'@main\b'), ('#Preview', r'#Preview\b'), ('import UIKit', r'^\s*import\s+UIKit\b'))


def check_fixture(path, label):
    content = text_file(path)
    for token, pattern in FORBIDDEN:
        match = re.search(pattern, content, re.MULTILINE)
        if match:
            line = content.count('\n', 0, match.start()) + 1
            raise SetupError('%s line %d contains "%s". The check is textual, so remove it from code and comments alike; fixtures must omit @main, #Preview, and UIKit (use a Simulator/Canvas workflow for iOS-only code).' % (label, line, token))
    if not re.search(r'\b(?:enum|struct|class)\s+PreviewFixture\b', content) or not re.search(r'\bstatic\s+func\s+makeView\s*\(', content):
        raise SetupError(label + ' needs PreviewFixture.static makeView().')


def validate_config(root, config, check_hashes=True):
    keys = {'schema_version', 'project_marker', 'source', 'fixture', 'component', 'platform', 'provenance'}
    has_live = isinstance(config, dict) and 'live_fixture' in config
    if has_live:
        keys = keys | {'live_fixture'}
    if not isinstance(config, dict) or set(config) != keys or type(config['schema_version']) is not int or config['schema_version'] != VERSION:
        raise SetupError('Unsupported or malformed configuration schema; configure again.')
    if config['platform'] != 'macos' or not isinstance(config['component'], str) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.]*', config['component']):
        raise SetupError('Configuration requires a component name and platform macos.')
    provenance = config['provenance']
    hash_keys = {'source_sha256', 'fixture_sha256'} | ({'live_fixture_sha256'} if has_live else set())
    if not isinstance(provenance, dict) or set(provenance) != hash_keys or any(not isinstance(value, str) or not re.fullmatch(r'[0-9a-f]{64}', value) for value in provenance.values()):
        raise SetupError('Malformed source/fixture provenance.')
    relative_path(root, config['project_marker'], 'project')
    source = relative_path(root, config['source'], 'swift')
    fixture = relative_path(root, config['fixture'], 'swift')
    if source == fixture or source.samefile(fixture):
        raise SetupError('Fixture must be a separate adapted file, not the production source.')
    check_fixture(fixture, 'Fixture')
    live = fixture
    if has_live:
        live = relative_path(root, config['live_fixture'], 'swift')
        if live == source or live.samefile(source) or live == fixture or live.samefile(fixture):
            raise SetupError('Live fixture must be a separate file from the source and the static fixture; omit --live-fixture to reuse the static one.')
        check_fixture(live, 'Live fixture')
    stale = digest(source) != provenance['source_sha256'] or digest(fixture) != provenance['fixture_sha256']
    if has_live:
        stale = stale or digest(live) != provenance['live_fixture_sha256']
    if check_hashes and stale:
        raise SetupError('Source or fixture changed: inspect and readapt the genuine component, then configure --replace.')
    return {'render': fixture, 'gallery': fixture, 'live': live}


def configure(root, args):
    source = relative_path(root, args.source, 'swift')
    fixture = relative_path(root, args.fixture, 'swift')
    config = {'schema_version': VERSION, 'project_marker': args.project,
              'source': args.source, 'fixture': args.fixture,
              'component': args.component, 'platform': 'macos',
              'provenance': {'source_sha256': digest(source), 'fixture_sha256': digest(fixture)}}
    if args.live_fixture:
        config['live_fixture'] = args.live_fixture
        config['provenance']['live_fixture_sha256'] = digest(relative_path(root, args.live_fixture, 'swift'))
    validate_config(root, config)
    path = config_path(root)
    if path.exists() and not args.replace:
        raise SetupError('Configuration already exists; inspect it before configure --replace.')
    path.parent.mkdir(exist_ok=True)
    # Exclusive creation preserves existing work. Replacement is an explicit CLI action.
    with path.open('w' if args.replace else 'x', encoding='utf-8') as stream:
        json.dump(config, stream, indent=2, sort_keys=True)
        stream.write('\n')
    result = {'config': CONFIG, 'component': args.component, 'platform': 'macos'}
    if args.live_fixture:
        result['live_fixture'] = args.live_fixture
    return result


def command(root, args):
    path = config_path(root)
    if not path.exists():
        raise SetupError('No ' + CONFIG + ' in this project; adapt a fixture and run configure first.')
    config = json.loads(path.read_text(encoding='utf-8'))
    fixture = validate_config(root, config)[args.mode]
    if args.mode != 'render' and 'fit' in (args.width, args.height):
        raise SetupError('fit sizes apply only to render; render with fit first, then pass the reported pixel size to gallery or live.')
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


BUNDLE_PREFIX = 'local.swiftui-component-preview.'
EXECUTABLE = 'SwiftUIPreview'


def owned_preview(app):
    """True only for a bundle that live.sh produced; anything else is never replaced."""
    try:
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    except (OSError, ValueError):
        return False
    return (isinstance(info, dict) and str(info.get('CFBundleIdentifier', '')).startswith(BUNDLE_PREFIX)
            and info.get('CFBundleExecutable') == EXECUTABLE)


def close_running(executable):
    """Stop processes started from exactly this preview executable; returns how many."""
    listing = subprocess.run(['/bin/ps', '-axo', 'pid=,comm='], capture_output=True, text=True, check=False).stdout
    pids = []
    for line in listing.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) == 2 and fields[1] == str(executable):
            pids.append(int(fields[0]))
    for sig in (signal.SIGTERM, signal.SIGKILL):
        alive = []
        for pid in pids:
            try:
                os.kill(pid, sig)
                alive.append(pid)
            except (ProcessLookupError, PermissionError):
                pass
        deadline = time.monotonic() + 3
        while alive and time.monotonic() < deadline:
            time.sleep(0.1)
            remaining = []
            for pid in alive:
                try:
                    os.kill(pid, 0)
                    remaining.append(pid)
                except (ProcessLookupError, PermissionError):
                    pass
            alive = remaining
        if not alive:
            break
    return len(pids)


def refresh(root, args):
    path = config_path(root)
    if not path.exists():
        raise SetupError('No ' + CONFIG + ' in this project; adapt a fixture and run configure first.')
    config = json.loads(path.read_text(encoding='utf-8'))
    validate_config(root, config, check_hashes=False)
    # Refresh is the agent's statement that the fixtures were readapted: record them anew.
    provenance = {'source_sha256': digest(relative_path(root, config['source'], 'swift')),
                  'fixture_sha256': digest(relative_path(root, config['fixture'], 'swift'))}
    if 'live_fixture' in config:
        provenance['live_fixture_sha256'] = digest(relative_path(root, config['live_fixture'], 'swift'))
    config['provenance'] = provenance
    fixture = validate_config(root, config)['live']
    if 'fit' in (args.width, args.height):
        raise SetupError('fit sizes apply only to render; pass numeric dimensions to refresh.')
    output = Path(args.output).expanduser()
    if not output.is_absolute():
        output = root / output
    if output.suffix != '.app':
        raise SetupError('Output extension must be .app.')
    if not output.parent.is_dir():
        raise SetupError('Output parent must already exist.')
    if output.is_symlink():
        raise SetupError('Output must not be a symlink.')
    output = output.parent.resolve() / output.name
    if output.exists() and not (output.is_dir() and owned_preview(output)):
        raise SetupError('Refusing to replace ' + output.name + ': it is not a preview app built by this skill.')
    staged = output.parent / ('.refresh-' + uuid.uuid4().hex + '.app')
    scripts = Path(__file__).resolve().parent
    build = subprocess.run(['/bin/bash', str(scripts / 'live.sh'), str(fixture), str(staged),
                            str(args.width), str(args.height), args.locale],
                           stdout=subprocess.DEVNULL, check=False)
    if build.returncode != 0:
        raise SetupError('Build failed; the previous app, its window, and the saved configuration are unchanged.')
    try:
        with path.open('w', encoding='utf-8') as stream:
            json.dump(config, stream, indent=2, sort_keys=True)
            stream.write('\n')
        closed = close_running(output / 'Contents/MacOS' / EXECUTABLE)
        if output.exists():
            shutil.rmtree(output)
        os.rename(staged, output)
    finally:
        if staged.exists():
            shutil.rmtree(staged, ignore_errors=True)
    launched = False
    if not args.no_launch:
        launched = subprocess.run(['/usr/bin/open', str(output)], check=False).returncode == 0
    return {'app': str(output), 'closed_previous_windows': closed, 'launched': launched,
            'note': 'A new process: view-local state in the previous window was not carried over.'}


def dimension(value):
    if value == 'fit':
        return value
    if not re.fullmatch(r'[1-9][0-9]{0,3}', value) or int(value) > 4096:
        raise argparse.ArgumentTypeError('Dimensions must be integers from 1 to 4096, or fit (render only).')
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
    refresh_parser = sub.add_parser('refresh', help='After fixtures were updated: record hashes, rebuild the live app at the same path, close its old window, and reopen.')
    for child in (discover_parser, configure_parser, run_parser, refresh_parser):
        child.add_argument('--root', required=True)
    for name in ('project', 'source', 'fixture', 'component'):
        configure_parser.add_argument('--' + name, required=True)
    configure_parser.add_argument('--live-fixture', help='Optional separate stateful fixture used only by run --mode live.')
    configure_parser.add_argument('--replace', action='store_true', help='Explicitly replace an inspected existing configuration after adaptation.')
    run_parser.add_argument('--mode', choices=('render', 'gallery', 'live'), required=True)
    run_parser.add_argument('--output', required=True)
    run_parser.add_argument('--width', type=dimension, default=480)
    run_parser.add_argument('--height', type=dimension, default=320)
    run_parser.add_argument('--locale', type=locale, default='en_US')
    run_parser.add_argument('--theme', choices=('light', 'dark'))
    run_parser.add_argument('--frame', action='store_true')
    refresh_parser.add_argument('--output', required=True)
    refresh_parser.add_argument('--width', type=dimension, default=640)
    refresh_parser.add_argument('--height', type=dimension, default=480)
    refresh_parser.add_argument('--locale', type=locale, default='en_US')
    refresh_parser.add_argument('--no-launch', action='store_true', help='Rebuild and replace only; do not open the app.')
    args = parser.parse_args()
    try:
        root = root_path(args.root)
        if args.action == 'discover':
            result = discover(root)
        elif args.action in ('configure', 'init'):
            result = configure(root, args)
        elif args.action == 'refresh':
            result = refresh(root, args)
        else:
            return subprocess.run(command(root, args), check=False).returncode
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except (SetupError, OSError, UnicodeError, ValueError) as error:
        print('bootstrap: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
