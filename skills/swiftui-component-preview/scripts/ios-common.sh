# Shared by the ios-*.sh helpers; source it, do not execute it.
# Callers define fail() and run with `set -euo pipefail`.

ios_minimum=17.0

ios_require_tools() {
    [[ "$(uname -s)" == Darwin ]] || fail 'iOS previews require macOS with Xcode and an iOS Simulator runtime.'
    command -v xcrun >/dev/null 2>&1 || fail 'Install Xcode to obtain swiftc and simctl.'
    command -v python3 >/dev/null 2>&1 || fail 'iOS previews require Python 3.8 or later (standard library only).'
    xcrun simctl help >/dev/null 2>&1 || fail 'simctl is unavailable: select a full Xcode with xcode-select, not only the command-line tools.'
    ios_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)" || fail 'The iOS Simulator SDK is missing; install the iOS platform in Xcode.'
}

# Language mode: Swift 6 with strict concurrency when the compiler has it, else Swift 5.
# PREVIEW_SWIFT_VERSION=5 compiles fixtures adapted from Swift 5 projects without strict checks.
ios_swift_flags() {
    local swift_mode="${PREVIEW_SWIFT_VERSION:-auto}"
    if [[ "$swift_mode" == auto ]]; then
        if xcrun swiftc -version 2>&1 | grep -Eq 'Swift version ([6-9]|[1-9][0-9])\.'; then swift_mode=6; else swift_mode=5; fi
    fi
    [[ "$swift_mode" == 5 || "$swift_mode" == 6 ]] || fail 'PREVIEW_SWIFT_VERSION must be 5, 6, or auto.'
    swift_flags=(-swift-version "$swift_mode")
    if [[ "$swift_mode" == 6 ]]; then swift_flags+=(-strict-concurrency=complete); fi
}

# Sets ios_udid, ios_device (display name with runtime) and ios_state.
# PREVIEW_IOS_DEVICE is a simulator name or UDID; without it a booted simulator wins,
# then the newest iPhone.
ios_select_device() {
    local selection
    selection="$(python3 - "${PREVIEW_IOS_DEVICE-}" "$ios_minimum" <<'PY'
import json, re, subprocess, sys
wanted, minimum = sys.argv[1], tuple(int(part) for part in sys.argv[2].split('.'))
listing = subprocess.run(['xcrun', 'simctl', 'list', 'devices', 'available', '-j'],
                         capture_output=True, text=True, check=False)
if listing.returncode != 0:
    sys.exit('simctl could not list simulators: ' + listing.stderr.strip())
found = []
for runtime, devices in json.loads(listing.stdout).get('devices', {}).items():
    match = re.search(r'\.iOS-(\d+)-(\d+)', runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    if version < minimum:
        continue
    for device in devices:
        if device.get('isAvailable', True):
            found.append((version, device))
if wanted:
    found = [item for item in found
             if item[1]['udid'].lower() == wanted.lower() or item[1]['name'].lower() == wanted.lower()]
    if not found:
        sys.exit('No available iOS %s+ simulator is named or identified "%s"; list them with: xcrun simctl list devices available' % (sys.argv[2], wanted))
elif not found:
    sys.exit('No available iOS %s+ simulator; add one in Xcode > Settings > Components.' % sys.argv[2])
found.sort(key=lambda item: (item[1]['state'] != 'Booted', not item[1]['name'].startswith('iPhone'),
                             [-part for part in item[0]], item[1]['name']))
version, device = found[0]
print('\t'.join((device['udid'], '%s (iOS %d.%d)' % (device['name'], version[0], version[1]), device['state'])))
PY
)" || exit 2
    IFS=$'\t' read -r ios_udid ios_device ios_state <<<"$selection"
}

# Boots the selected simulator when needed and waits until it can launch apps.
ios_boot_device() {
    if [[ "$ios_state" != Booted ]]; then
        xcrun simctl boot "$ios_udid" >/dev/null 2>&1 || true
        xcrun simctl bootstatus "$ios_udid" -b >/dev/null 2>&1 || fail "Could not boot $ios_device."
        printf '%s: booted %s; it stays booted for later previews (stop it with: xcrun simctl shutdown %s)\n' \
            "$ios_tag" "$ios_device" "$ios_udid" >&2
    fi
}

# ios_write_info app bundle-identifier: metadata as data, never generated Swift source.
ios_write_info() {
    python3 - "$1" "$2" "$ios_minimum" <<'PY'
import pathlib, plistlib, sys
orientations = ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft',
                'UIInterfaceOrientationLandscapeRight']
info = {
    'CFBundleExecutable': 'SwiftUIPreview',
    'CFBundleIdentifier': sys.argv[2],
    'CFBundleName': 'SwiftUI Preview',
    'CFBundleDisplayName': 'SwiftUI Preview',
    'CFBundlePackageType': 'APPL',
    'CFBundleVersion': '1',
    'CFBundleShortVersionString': '1.0',
    'CFBundleSupportedPlatforms': ['iPhoneSimulator'],
    'MinimumOSVersion': sys.argv[3],
    'UIDeviceFamily': [1, 2],
    'UILaunchScreen': {},
    'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False},
    'UISupportedInterfaceOrientations': orientations,
    'UISupportedInterfaceOrientations~ipad': orientations + ['UIInterfaceOrientationPortraitUpsideDown'],
}
(pathlib.Path(sys.argv[1]) / 'Info.plist').write_bytes(plistlib.dumps(info))
PY
}

# ios_compile_catalyst host.swift fixture.swift executable module-cache: the same sources as a
# Mac Catalyst binary, which runs in an ordinary Mac window without a simulator.
ios_compile_catalyst() {
    local sdk
    sdk="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)" || fail 'The macOS SDK is missing; install Xcode.'
    [[ -d "$sdk/System/iOSSupport/System/Library/Frameworks/UIKit.framework" ]] \
        || fail 'This macOS SDK has no Mac Catalyst support.'
    ios_swift_flags
    xcrun --sdk macosx swiftc "${swift_flags[@]}" -parse-as-library \
        -target "$(uname -m)-apple-ios${ios_minimum}-macabi" -sdk "$sdk" \
        -Fsystem "$sdk/System/iOSSupport/System/Library/Frameworks" \
        -I "$sdk/System/iOSSupport/usr/lib/swift" -L "$sdk/System/iOSSupport/usr/lib/swift" \
        -module-name SwiftUIPreview -module-cache-path "$4" \
        "$1" "$2" -o "$3"
}

# ios_install_exclusive staged.app output.app: Darwin's exclusive rename installs atomically
# without replacing a raced-in path.
ios_install_exclusive() {
    python3 - "$1" "$2" <<'PY'
import ctypes, os, sys
libc = ctypes.CDLL(None, use_errno=True)
rename = libc.renamex_np
rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
rename.restype = ctypes.c_int
if rename(os.fsencode(sys.argv[1]), os.fsencode(sys.argv[2]), 4) != 0:  # RENAME_EXCL
    error = ctypes.get_errno()
    raise OSError(error, os.strerror(error), sys.argv[2])
PY
}

# ios_compile host.swift fixture.swift app module-cache: the host and trusted fixture are the complete source list.
ios_compile() {
    ios_swift_flags
    xcrun --sdk iphonesimulator swiftc "${swift_flags[@]}" -parse-as-library \
        -target "$(uname -m)-apple-ios${ios_minimum}-simulator" -sdk "$ios_sdk" \
        -module-name SwiftUIPreview -module-cache-path "$4" \
        "$1" "$2" -o "$3/SwiftUIPreview"
}
