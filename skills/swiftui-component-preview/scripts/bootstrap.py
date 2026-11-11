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
        ('AppKit import', r'^\s*(?:@\w+\s+)?import\s+(?:AppKit|Cocoa)\b'),
        ('iOS conditional', r'#if\s+os\(iOS\)'),
        ('macOS conditional', r'#if\s+os\(macOS\)'),
        ('macOS platform declaration', r'\.macOS\s*\('),
        ('iOS platform declaration', r'\.iOS\s*\('),
        ('iOS Xcode platform', r'\b(?:iphoneos|iphonesimulator)\b'),
        ('macOS Xcode platform', r'\bmacosx\b'),
        ('iOS deployment target', r'\bIPHONEOS_DEPLOYMENT_TARGET\b'),
        ('macOS deployment target', r'\bMACOSX_DEPLOYMENT_TARGET\b'),
    ):
        if re.search(pattern, text, re.MULTILINE):
            signals.append(label)
    return signals


def suggest_platform(signals):
    """ios, macos, both or unknown from textual evidence.

    `#if os(...)` conditionals are left out: they mark shared code, not a target.
    """
    ios = any(label.startswith(('iOS ', 'UIKit')) and 'conditional' not in label for label in signals)
    mac = any(label.startswith(('macOS ', 'AppKit')) and 'conditional' not in label for label in signals)
    return 'both' if ios and mac else 'ios' if ios else 'macos' if mac else 'unknown'


def project_evidence(root, marker):
    """Evidence for Package.swift, an .xcodeproj, or the projects an .xcworkspace lists."""
    if marker.name == 'Package.swift':
        return evidence(text_file(marker))
    projects = [marker]
    if marker.suffix == '.xcworkspace':
        listing = marker / 'contents.xcworkspacedata'
        projects = []
        if listing.is_file() and not listing.is_symlink():
            for reference in re.findall(r'location\s*=\s*"(?:group|container):([^"]+\.xcodeproj)"', text_file(listing)):
                candidate = (marker.parent / reference).resolve()
                if root in candidate.parents and candidate.is_dir():
                    projects.append(candidate)
    signals = []
    for project in projects:
        metadata = project / 'project.pbxproj'
        if metadata.is_file() and not metadata.is_symlink():
            signals += [label for label in evidence(text_file(metadata)) if label not in signals]
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
                signals = project_evidence(root, path)
                projects.append({'path': path.relative_to(root).as_posix(),
                                 'kind': path.suffix[1:], 'platform_evidence': signals,
                                 'suggested_platform': suggest_platform(signals)})
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
                                 'platform_evidence': evidence(content),
                                 'suggested_platform': suggest_platform(evidence(content))})
            elif re.search(r'^\s*import\s+SwiftUI\b|#Preview\b', content, re.MULTILINE):
                sources.append({'path': relative, 'has_preview': bool(re.search(r'#Preview\b', content)),
                                'platform_evidence': evidence(content),
                                'suggested_platform': suggest_platform(evidence(content)),
                                'declared_views': re.findall(r'\bstruct\s+(\w+)\s*:\s*(?:SwiftUI\.)?View\b', content)})
    projects.sort(key=lambda item: item['path'])
    sources.sort(key=lambda item: item['path'])
    return {'schema_version': VERSION, 'projects': projects, 'sources': sources,
            'selection_required': {'project': len(projects) != 1, 'source': len(sources) != 1},
            'skipped_symlinks': sorted(skipped),
            'notes': ['Text evidence only; missing platform evidence is unknown, not unsupported.',
                      'suggested_platform is ios, macos, both or unknown; configure resolves it the same way and needs --platform when the result is both or unknown.',
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


PLATFORMS = ('macos', 'ios')
FORBIDDEN = (('@main', r'@main\b'), ('#Preview', r'#Preview\b'), ('import UIKit', r'^\s*import\s+UIKit\b'))


def check_fixture(path, label, platform='macos'):
    content = text_file(path)
    for token, pattern in FORBIDDEN:
        if platform == 'ios' and token == 'import UIKit':
            continue  # The simulator host is a UIKit application.
        match = re.search(pattern, content, re.MULTILINE)
        if match:
            line = content.count('\n', 0, match.start()) + 1
            raise SetupError('%s line %d contains "%s". The check is textual, so remove it from code and comments alike; fixtures must omit @main and #Preview, and macOS fixtures must omit UIKit (configure --platform ios for iOS-only code).' % (label, line, token))
    if not re.search(r'\b(?:enum|struct|class)\s+PreviewFixture\b', content) or not re.search(r'\bstatic\s+func\s+makeView\s*\(', content):
        raise SetupError(label + ' needs PreviewFixture.static makeView().')


def validate_config(root, config, check_hashes=True):
    keys = {'schema_version', 'project_marker', 'source', 'fixture', 'component', 'platform', 'provenance'}
    has_live = isinstance(config, dict) and 'live_fixture' in config
    if has_live:
        keys = keys | {'live_fixture'}
    if not isinstance(config, dict) or set(config) != keys or type(config['schema_version']) is not int or config['schema_version'] != VERSION:
        raise SetupError('Unsupported or malformed configuration schema; configure again.')
    if config['platform'] not in PLATFORMS or not isinstance(config['component'], str) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.]*', config['component']):
        raise SetupError('Configuration requires a component name and platform macos or ios.')
    provenance = config['provenance']
    hash_keys = {'source_sha256', 'fixture_sha256'} | ({'live_fixture_sha256'} if has_live else set())
    if not isinstance(provenance, dict) or set(provenance) != hash_keys or any(not isinstance(value, str) or not re.fullmatch(r'[0-9a-f]{64}', value) for value in provenance.values()):
        raise SetupError('Malformed source/fixture provenance.')
    relative_path(root, config['project_marker'], 'project')
    source = relative_path(root, config['source'], 'swift')
    fixture = relative_path(root, config['fixture'], 'swift')
    if source == fixture or source.samefile(fixture):
        raise SetupError('Fixture must be a separate adapted file, not the production source.')
    check_fixture(fixture, 'Fixture', config['platform'])
    live = fixture
    if has_live:
        live = relative_path(root, config['live_fixture'], 'swift')
        if live == source or live.samefile(source) or live == fixture or live.samefile(fixture):
            raise SetupError('Live fixture must be a separate file from the source and the static fixture; omit --live-fixture to reuse the static one.')
        check_fixture(live, 'Live fixture', config['platform'])
    stale = digest(source) != provenance['source_sha256'] or digest(fixture) != provenance['fixture_sha256']
    if has_live:
        stale = stale or digest(live) != provenance['live_fixture_sha256']
    if check_hashes and stale:
        raise SetupError('Source or fixture changed: inspect and readapt the genuine component, then configure --replace.')
    return {'render': fixture, 'gallery': fixture, 'live': live}


def resolve_platform(root, args, source):
    """The platform to save and where it came from: the request, the source, or the project."""
    if args.platform != 'auto':
        return args.platform, 'explicit'
    # A framework import in the component itself outranks what the project as a whole targets.
    from_source = suggest_platform([label for label in evidence(text_file(source)) if 'import' in label])
    if from_source in PLATFORMS:
        return from_source, 'source'
    signals = project_evidence(root, relative_path(root, args.project, 'project'))
    from_project = suggest_platform(signals)
    if from_project in PLATFORMS:
        return from_project, 'project'
    found = 'both iOS and macOS (%s)' % ', '.join(signals) if from_project == 'both' else 'no platform'
    raise SetupError('Cannot choose a platform: %s declares %s. Ask the user whether to preview for iOS/iPadOS or macOS, then pass --platform ios or --platform macos.' % (args.project, found))


def configure(root, args):
    source = relative_path(root, args.source, 'swift')
    fixture = relative_path(root, args.fixture, 'swift')
    platform, platform_source = resolve_platform(root, args, source)
    config = {'schema_version': VERSION, 'project_marker': args.project,
              'source': args.source, 'fixture': args.fixture,
              'component': args.component, 'platform': platform,
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
    result = {'config': CONFIG, 'component': args.component, 'platform': platform, 'platform_source': platform_source}
    if args.live_fixture:
        result['live_fixture'] = args.live_fixture
    return result


def check_request(config, args, mode):
    """Reject size and simulator options that the saved platform or the mode cannot honor."""
    ios = config['platform'] == 'ios'
    if not ios and (getattr(args, 'device', None) or getattr(args, 'scale', None)):
        raise SetupError('--device and --scale apply only to platform ios; this project is configured for macos.')
    if 'screen' in (args.width, args.height):
        if not ios:
            raise SetupError('screen sizes apply only to platform ios.')
        if mode == 'live':
            raise SetupError('The iOS live preview always fills the simulator screen; omit --width and --height.')
        if args.width != args.height:
            raise SetupError('screen covers the whole device: pass it for both --width and --height.')
    if mode != 'render' and 'fit' in (args.width, args.height):
        raise SetupError('fit sizes apply only to render; render with fit first, then pass the reported size to gallery or live.')
    if mode == 'live' and getattr(args, 'scale', None):
        raise SetupError('--scale applies only to render and gallery.')
    live_host = getattr(args, 'live_host', None)
    if live_host and (not ios or mode != 'live'):
        raise SetupError('--live-host applies only to live previews on platform ios.')
    if live_host == 'catalyst' and getattr(args, 'device', None):
        raise SetupError('--device selects a simulator; the catalyst live host runs in a Mac window.')


def command(root, args):
    path = config_path(root)
    if not path.exists():
        raise SetupError('No ' + CONFIG + ' in this project; adapt a fixture and run configure first.')
    config = json.loads(path.read_text(encoding='utf-8'))
    fixture = validate_config(root, config)[args.mode]
    check_request(config, args, args.mode)
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
    info = None
    # macOS bundles keep Info.plist under Contents; iOS bundles are flat.
    for location in ('Contents/Info.plist', 'Info.plist'):
        try:
            info = plistlib.loads((app / location).read_bytes())
            break
        except (OSError, ValueError):
            continue
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
    check_request(config, args, 'live')
    # The Catalyst host is a Mac app: it is replaced, closed and opened like the macOS one.
    ios = config['platform'] == 'ios' and args.live_host != 'catalyst'
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
    environment = helper_env(args, config['platform'])
    if ios:
        # The simulator keeps one installed app per output path, whatever the staging name.
        environment['PREVIEW_IOS_BUNDLE_SEED'] = str(output)
    build = subprocess.run(['/bin/bash', str(scripts / 'live.sh'), str(fixture), str(staged),
                            str(args.width), str(args.height), args.locale],
                           stdout=subprocess.DEVNULL, env=environment, check=False)
    if build.returncode != 0:
        raise SetupError('Build failed; the previous app, its window, and the saved configuration are unchanged.')
    try:
        with path.open('w', encoding='utf-8') as stream:
            json.dump(config, stream, indent=2, sort_keys=True)
            stream.write('\n')
        closed = 0 if ios else close_running(output / 'Contents/MacOS' / EXECUTABLE)
        if output.exists():
            shutil.rmtree(output)
        os.rename(staged, output)
    finally:
        if staged.exists():
            shutil.rmtree(staged, ignore_errors=True)
    launched = False
    if not args.no_launch:
        launch = ['/bin/bash', str(scripts / 'ios-launch.sh'), str(output)] if ios else ['/usr/bin/open', str(output)]
        # The launcher reports its device on stdout; keep this command's stdout pure JSON.
        launched = subprocess.run(launch, stdout=subprocess.DEVNULL, env=environment, check=False).returncode == 0
    result = {'app': str(output), 'closed_previous_windows': closed, 'launched': launched,
              'note': 'A new process: view-local state in the previous window was not carried over.'}
    if ios:
        result['note'] = 'Reinstalled on the simulator and relaunched: view-local state was not carried over.'
    return result


def helper_env(args, platform):
    """Environment for the shell helpers: platform, language mode and simulator options."""
    environment = dict(os.environ, PREVIEW_PLATFORM=platform)
    if args.swift_version:
        environment['PREVIEW_SWIFT_VERSION'] = args.swift_version
    if args.device:
        environment['PREVIEW_IOS_DEVICE'] = args.device
    if getattr(args, 'scale', None):
        environment['PREVIEW_IOS_SCALE'] = str(args.scale)
    if getattr(args, 'live_host', None):
        environment['PREVIEW_IOS_LIVE_HOST'] = args.live_host
    return environment


def dimension(value):
    if value in ('fit', 'screen'):
        return value
    if not re.fullmatch(r'[1-9][0-9]{0,3}', value) or int(value) > 4096:
        raise argparse.ArgumentTypeError('Dimensions must be integers from 1 to 4096, fit (render only), or screen (platform ios).')
    return int(value)


def device(value):
    if not value or len(value) > 128 or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9 ()._\-]*', value):
        raise argparse.ArgumentTypeError('Supply a simulator name such as "iPhone 17" or its UDID.')
    return value


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
    configure_parser.add_argument('--platform', choices=PLATFORMS + ('auto',), default='auto', help='macos renders natively; ios renders and runs in an iOS Simulator (iPhone or iPad). auto (default) reads it from the source imports, then the project, and stops when they say both or nothing.')
    configure_parser.add_argument('--replace', action='store_true', help='Explicitly replace an inspected existing configuration after adaptation.')
    run_parser.add_argument('--mode', choices=('render', 'gallery', 'live'), required=True)
    run_parser.add_argument('--output', required=True)
    run_parser.add_argument('--width', type=dimension, default=480)
    run_parser.add_argument('--height', type=dimension, default=320)
    run_parser.add_argument('--locale', type=locale, default='en_US')
    run_parser.add_argument('--theme', choices=('light', 'dark'))
    run_parser.add_argument('--frame', action='store_true')
    run_parser.add_argument('--scale', type=int, choices=(1, 2, 3), help='Platform ios, render and gallery: pixels per point; default 2.')
    refresh_parser.add_argument('--output', required=True)
    refresh_parser.add_argument('--width', type=dimension, default=640)
    refresh_parser.add_argument('--height', type=dimension, default=480)
    refresh_parser.add_argument('--locale', type=locale, default='en_US')
    refresh_parser.add_argument('--no-launch', action='store_true', help='Rebuild and replace only; do not open the app.')
    for child in (run_parser, refresh_parser):
        child.add_argument('--device', type=device, help='Platform ios: simulator name or UDID; default is a booted simulator, then the newest iPhone.')
        child.add_argument('--live-host', choices=('simulator', 'catalyst'), help='Platform ios, live only: simulator (default) runs on a simulator device; catalyst opens an ordinary Mac window with a control bar (an iPad interface on the Mac).')
        child.add_argument('--swift-version', choices=('5', '6'), help='Language mode for the build; default is 6 with strict concurrency when the compiler supports it, else 5.')
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
            argv = command(root, args)
            platform = json.loads(config_path(root).read_text(encoding='utf-8'))['platform']
            return subprocess.run(argv, env=helper_env(args, platform), check=False).returncode
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except (SetupError, OSError, UnicodeError, ValueError) as error:
        print('bootstrap: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
