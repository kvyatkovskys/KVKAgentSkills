#!/bin/bash
set -euo pipefail

# Builds a live preview app for an iOS fixture; it does not install or launch it.
# The arguments match live.sh. PREVIEW_IOS_LIVE_HOST chooses where it runs:
#   simulator (default)  an iOS Simulator app; width and height are validated but unused,
#                        because the device supplies the viewport.
#   catalyst             a Mac Catalyst app: an ordinary Mac window with a control bar,
#                        opened at width x height. It is an iPad interface on the Mac.

usage() { printf 'Usage: %s fixture.swift output.app width height locale\n' "$0" >&2; }
ios_tag=live
fail() { printf 'live: %s\n' "$1" >&2; exit 2; }
[[ $# -eq 5 ]] || { usage; exit 2; }
fixture="$1"
output="$2"
width="$3"
height="$4"
locale="$5"
for dimension in "$width" "$height"; do
    [[ "$dimension" =~ ^[1-9][0-9]{0,3}$ ]] || fail 'Dimensions must be integers from 1 to 4096.'
    (( dimension <= 4096 )) || fail 'Dimensions must be integers from 1 to 4096.'
done
[[ ${#locale} -le 128 && "$locale" =~ ^[A-Za-z][A-Za-z0-9_@=.-]*$ ]] || fail 'Supply a locale identifier such as en_US or de-DE.'
[[ -f "$fixture" && -r "$fixture" && "$fixture" == *.swift ]] || fail 'Fixture must be a readable .swift file.'
[[ "$output" == *.app ]] || fail 'Output must have an .app extension.'
[[ -d "$(dirname "$output")" ]] || fail 'Output parent directory must already exist.'
[[ ! -e "$output" && ! -L "$output" ]] || fail 'Output must be a new path, not an existing file, directory or symlink.'
live_host="${PREVIEW_IOS_LIVE_HOST:-simulator}"
[[ "$live_host" == simulator || "$live_host" == catalyst ]] || fail 'PREVIEW_IOS_LIVE_HOST must be simulator or catalyst.'
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=ios-common.sh
source "$script_dir/ios-common.sh"
if [[ "$live_host" == simulator ]]; then
    ios_require_tools
else
    [[ "$(uname -s)" == Darwin ]] || fail 'Live preview builds require macOS and Xcode.'
    command -v xcrun >/dev/null 2>&1 || fail 'Install Xcode to obtain swiftc.'
    command -v python3 >/dev/null 2>&1 || fail 'Live preview builds require Python 3.8 or later (standard library only).'
fi
fixture="$(cd "$(dirname "$fixture")" && pwd -P)/$(basename "$fixture")"
output_parent="$(cd "$(dirname "$output")" && pwd -P)"
output="$output_parent/$(basename "$output")"
stage_dir="$(mktemp -d "$output_parent/.swiftui-live.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
app="$stage_dir/Preview.app"

if [[ "$live_host" == catalyst ]]; then
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    # Pass validated values as data, never as generated Swift source.
    python3 - "$app" "$width" "$height" "$locale" "$ios_minimum" <<'PY'
import pathlib, plistlib, sys, uuid
app = pathlib.Path(sys.argv[1])
info = {
    'CFBundleExecutable': 'SwiftUIPreview',
    'CFBundleIdentifier': 'local.swiftui-component-preview.' + uuid.uuid4().hex,
    'CFBundleName': 'SwiftUI Component Preview',
    'CFBundleDisplayName': 'SwiftUI Component Preview',
    'CFBundlePackageType': 'APPL',
    'CFBundleVersion': '1',
    'CFBundleShortVersionString': '1.0',
    'CFBundleSupportedPlatforms': ['MacOSX'],
    'LSMinimumSystemVersion': '14.0',
    'MinimumOSVersion': sys.argv[5],
    'UIDeviceFamily': [2],
    'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False},
    'NSHighResolutionCapable': True,
}
config = {'width': int(sys.argv[2]), 'height': int(sys.argv[3]), 'locale': sys.argv[4]}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
(app/'Contents/Resources/PreviewConfiguration.plist').write_bytes(plistlib.dumps(config))
PY
    ios_compile_catalyst "$script_dir/IOSCatalystHost.swift" "$fixture" "$app/Contents/MacOS/SwiftUIPreview" "$stage_dir/module-cache"
    rm -rf "$stage_dir/module-cache"
    ios_install_exclusive "$app" "$output"
    printf 'Built Mac Catalyst live preview (not launched): %s\n' "$output"
    exit 0
fi

mkdir -p "$app"

# One identifier per output path, so a rebuild replaces the app already on the simulator.
# refresh builds at a staging path and passes the final one as PREVIEW_IOS_BUNDLE_SEED.
bundle_id="local.swiftui-component-preview.live.$(printf '%s' "${PREVIEW_IOS_BUNDLE_SEED:-$output}" | shasum -a 256 | cut -c1-16)"
ios_write_info "$app" "$bundle_id"
# Pass validated values as data, never as generated Swift source.
python3 - "$app" "$locale" <<'PY'
import pathlib, plistlib, sys
(pathlib.Path(sys.argv[1]) / 'PreviewConfiguration.plist').write_bytes(plistlib.dumps({'locale': sys.argv[2]}))
PY
ios_compile "$script_dir/IOSLiveHost.swift" "$fixture" "$app" "$stage_dir/module-cache"
rm -rf "$stage_dir/module-cache"

ios_install_exclusive "$app" "$output"
printf 'Built iOS Simulator live preview (not installed or launched): %s\n' "$output"
