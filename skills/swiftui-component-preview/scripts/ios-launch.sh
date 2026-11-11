#!/bin/bash
set -euo pipefail

# Installs and launches a live preview app built by ios-live.sh on an iOS Simulator.
# Environment: PREVIEW_IOS_DEVICE (name or UDID; default is a booted simulator, then the
# newest iPhone), PREVIEW_IOS_HEADLESS=1 to leave the Simulator application closed.

usage() { printf 'Usage: %s preview.app\n' "$0" >&2; }
ios_tag=launch
fail() { printf 'launch: %s\n' "$1" >&2; exit 2; }
[[ $# -eq 1 ]] || { usage; exit 2; }
app="$1"
[[ "$app" == *.app && -d "$app" && ! -L "$app" ]] || fail 'Supply the .app directory built by ios-live.sh.'
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=ios-common.sh
source "$script_dir/ios-common.sh"
ios_require_tools
app="$(cd "$app" && pwd -P)"

# Only bundles this skill built are installed; anything else is refused.
bundle_id="$(python3 - "$app" <<'PY'
import pathlib, plistlib, sys
try:
    info = plistlib.loads((pathlib.Path(sys.argv[1]) / 'Info.plist').read_bytes())
except (OSError, ValueError):
    sys.exit(1)
identifier = str(info.get('CFBundleIdentifier', ''))
if not identifier.startswith('local.swiftui-component-preview.live.') or info.get('CFBundleExecutable') != 'SwiftUIPreview':
    sys.exit(1)
print(identifier)
PY
)" || fail 'Not an iOS live preview built by this skill.'

ios_select_device
ios_boot_device
xcrun simctl install "$ios_udid" "$app" || fail "Could not install the preview on $ios_device."
xcrun simctl launch --terminate-running-process "$ios_udid" "$bundle_id" >/dev/null \
    || fail "Could not launch the preview on $ios_device."
# Show the device window: Simulator.app, or Device Hub in Xcode versions that ship it instead.
if [[ "${PREVIEW_IOS_HEADLESS:-0}" != 1 ]]; then
    developer_dir="$(xcode-select -p 2>/dev/null || true)"
    if [[ -d "$developer_dir/Applications/Simulator.app" ]]; then
        open "$developer_dir/Applications/Simulator.app" --args -CurrentDeviceUDID "$ios_udid" >/dev/null 2>&1 || true
    elif [[ -d "$developer_dir/../Applications/DeviceHub.app" ]]; then
        open "$developer_dir/../Applications/DeviceHub.app" >/dev/null 2>&1 || true
    else
        printf 'launch: no Simulator or Device Hub application found in Xcode; the preview runs without a window\n' >&2
    fi
fi
printf 'Launched %s on %s (%s)\n' "$bundle_id" "$ios_device" "$ios_udid"
