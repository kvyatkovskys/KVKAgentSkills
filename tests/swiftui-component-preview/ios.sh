#!/bin/bash
# iOS Simulator renders, gallery, live build and launch. Skips when no simulator is available.
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../skills/swiftui-component-preview" && pwd -P)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/component-ios-test.XXXXXX")"
launched_bundle=''
device=''
cleanup() {
    [[ -z "$launched_bundle" ]] || xcrun simctl uninstall "$device" "$launched_bundle" >/dev/null 2>&1 || true
    rm -rf "$test_dir"
}
trap cleanup EXIT
mkdir -p "$test_dir/path with spaces" "$test_dir/compiler-temporary-files"
export TMPDIR="$test_dir/compiler-temporary-files"
export PREVIEW_GALLERY_WEBP=0
export PREVIEW_IOS_HEADLESS=1
export PREVIEW_IOS_TIMEOUT="${PREVIEW_IOS_TIMEOUT:-240}"
renderer="$skill_dir/scripts/ios-render.sh"

cat >"$test_dir/path with spaces/Chip.swift" <<'SWIFT'
import SwiftUI
import UIKit

@MainActor enum PreviewFixture {
    static func makeView() -> some View {
        Label(UIDevice.current.userInterfaceIdiom == .pad ? "Tablet" : "Phone", systemImage: "shippingbox.fill")
            .padding(12)
            .background(.orange.opacity(0.2), in: Capsule())
    }
}
SWIFT
fixture="$test_dir/path with spaces/Chip.swift"

expect_failure() {
    if bash "$renderer" "$@" >"$test_dir/failure.log" 2>&1; then
        printf 'Expected failure for arguments: %s\n' "$*" >&2
        exit 1
    fi
    [[ ! -e "$test_dir/invalid.png" ]] || { printf 'Invalid input produced an output file\n' >&2; exit 1; }
}

# Rejected before any build or simulator use.
for width in 0 -1 nan 1.5 4097 999999999999999999999; do
    expect_failure "$fixture" "$test_dir/invalid.png" "$width" 320 light en_US
done
expect_failure "$fixture" "$test_dir/invalid.png" screen 320 light en_US
expect_failure "$fixture" "$test_dir/invalid.png" 320 screen light en_US
expect_failure "$fixture" "$test_dir/invalid.png" 390 320 sepia en_US
expect_failure "$fixture" "$test_dir/invalid.png" 390 320 light ''
expect_failure "$fixture" "$test_dir/invalid.png" 390 320 light en_US --unknown
expect_failure "$test_dir/missing.swift" "$test_dir/invalid.png" 390 320 light en_US
expect_failure "$fixture" "$test_dir/invalid.jpg" 390 320 light en_US
PREVIEW_IOS_SCALE=4 expect_failure "$fixture" "$test_dir/invalid.png" 390 320 light en_US
if PREVIEW_PLATFORM=tvos bash "$skill_dir/scripts/render.sh" "$fixture" "$test_dir/invalid.png" 390 320 light en_US >/dev/null 2>&1; then
    printf 'Expected an unknown platform to be rejected\n' >&2
    exit 1
fi

# Mac Catalyst live host: needs no simulator. Flat arguments match live.sh.
catalyst="$test_dir/path with spaces/Catalyst Preview.app"
if PREVIEW_PLATFORM=ios PREVIEW_IOS_LIVE_HOST=window bash "$skill_dir/scripts/live.sh" "$fixture" "$test_dir/invalid.app" 430 600 en_US >/dev/null 2>&1; then
    printf 'Expected an unknown live host to be rejected\n' >&2
    exit 1
fi
[[ ! -e "$test_dir/invalid.app" ]]
PREVIEW_PLATFORM=ios PREVIEW_IOS_LIVE_HOST=catalyst bash "$skill_dir/scripts/live.sh" "$fixture" "$catalyst" 430 600 fr_FR >/dev/null
/usr/bin/python3 - "$catalyst" <<'CHECK'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleExecutable'] == 'SwiftUIPreview'
assert info['UIDeviceFamily'] == [2]
assert info['CFBundleIdentifier'].startswith('local.swiftui-component-preview.')
assert plistlib.loads((app/'Contents/Resources/PreviewConfiguration.plist').read_bytes()) == {'width': 430, 'height': 600, 'locale': 'fr_FR'}
assert sorted(str(p.relative_to(app)) for p in app.rglob('*') if p.is_file()) == [
    'Contents/Info.plist', 'Contents/MacOS/SwiftUIPreview', 'Contents/Resources/PreviewConfiguration.plist']
CHECK
/usr/bin/vtool -show-build "$catalyst/Contents/MacOS/SwiftUIPreview" | grep -q 'MACCATALYST'
for leftover in "$test_dir/path with spaces"/.swiftui-live.*; do
    [[ ! -e "$leftover" ]] || { printf 'Builder left staging files\n' >&2; exit 1; }
done
# Start the executable directly to read the viewport it settles on; a window appears briefly.
# Skipped on CI, where no window server session may be available.
if [[ -z "${CI-}" ]]; then
    "$catalyst/Contents/MacOS/SwiftUIPreview" >"$test_dir/catalyst.log" 2>/dev/null &
    catalyst_pid=$!
    sleep 6
    kill "$catalyst_pid" 2>/dev/null || true
    wait "$catalyst_pid" 2>/dev/null || true
    settled="$(sed -n 's/^viewport //p' "$test_dir/catalyst.log" | tail -n 1)"
    [[ -n "$settled" ]] || { printf 'Catalyst host reported no viewport\n' >&2; exit 1; }
    (( ${settled%x*} >= 428 && ${settled%x*} <= 432 && ${settled#*x} >= 598 && ${settled#*x} <= 602 )) \
        || { printf 'Catalyst window opened at %s, expected about 430x600\n' "$settled" >&2; exit 1; }
fi

if ! xcrun simctl list devices available 2>/dev/null | grep -Eq '^-- iOS (1[7-9]|[2-9][0-9])\.'; then
    printf 'SKIP: no available iOS 17+ simulator; input validation and the Mac Catalyst live build verified only.\n'
    exit 0
fi

check_png() {
    local file="$1" width="$2" height="$3"
    [[ -s "$file" ]]
    /usr/bin/sips -g pixelWidth -g pixelHeight "$file" >"$test_dir/dimensions.txt"
    awk -v width="$width" -v height="$height" '
        /pixelWidth:/ { actualWidth = $2 }
        /pixelHeight:/ { actualHeight = $2 }
        END { exit !(actualWidth == width && actualHeight == height) }
    ' "$test_dir/dimensions.txt"
}
check_cleanup() {
    local leftover
    for leftover in "$TMPDIR"/swiftui-component-preview.* "$TMPDIR"/swiftui-component-gallery.* "$test_dir"/.swiftui-render.*; do
        [[ ! -e "$leftover" ]] || { printf 'Helper left temporary files: %s\n' "$leftover" >&2; exit 1; }
    done
}

printf 'This is not valid Swift.\n' >"$test_dir/Broken.swift"
expect_failure "$test_dir/Broken.swift" "$test_dir/invalid.png" 390 320 light en_US
check_cleanup

# Fixed viewport at the default 2x, through the PREVIEW_PLATFORM switch of render.sh.
PREVIEW_PLATFORM=ios bash "$skill_dir/scripts/render.sh" "$fixture" "$test_dir/path with spaces/light.png" 200 80 light en_US 2>"$test_dir/render.log"
check_png "$test_dir/path with spaces/light.png" 400 160
device="$(sed -n 's/^render: \(.*\) (iOS [0-9.]*), content .*/\1/p' "$test_dir/render.log")"
[[ -n "$device" ]] || { printf 'Renderer did not report its simulator\n' >&2; exit 1; }
export PREVIEW_IOS_DEVICE="$device"
PREVIEW_IOS_SCALE=1 bash "$renderer" "$fixture" "$test_dir/dark.png" 200 80 dark en_US 2>/dev/null
check_png "$test_dir/dark.png" 200 80
PREVIEW_IOS_SCALE=1 bash "$renderer" "$fixture" "$test_dir/light1.png" 200 80 light en_US 2>/dev/null
if cmp -s "$test_dir/light1.png" "$test_dir/dark.png"; then
    printf 'Light and dark images unexpectedly match\n' >&2
    exit 1
fi
PREVIEW_IOS_SCALE=3 bash "$renderer" "$fixture" "$test_dir/framed.png" 200 80 light en_US --frame 2>/dev/null
check_png "$test_dir/framed.png" 744 504
bash "$renderer" "$fixture" "$test_dir/fit.png" fit fit light en_US 2>"$test_dir/fit.log"
fitted="$(sed -n 's/^render: fitted content size //p' "$test_dir/fit.log")"
(( ${fitted%x*} > 1 && ${fitted#*x} > 1 ))
check_png "$test_dir/fit.png" $(( ${fitted%x*} * 2 )) $(( ${fitted#*x} * 2 ))
# The whole device screen: its size in points is reported and the image matches it.
PREVIEW_IOS_SCALE=1 bash "$renderer" "$fixture" "$test_dir/screen.png" screen screen light en_US 2>"$test_dir/screen.log"
screen="$(sed -n 's/^render: .*, content \([0-9]*x[0-9]*\) pt at 1x$/\1/p' "$test_dir/screen.log")"
(( ${screen%x*} >= 320 && ${screen#*x} >= 320 ))
check_png "$test_dir/screen.png" "${screen%x*}" "${screen#*x}"
# A list has no ideal height on iOS; the error says what to pass instead.
cat >"$test_dir/List.swift" <<'SWIFT'
import SwiftUI
@MainActor enum PreviewFixture {
    static func makeView() -> some View { List { Text("Row") } }
}
SWIFT
expect_failure "$test_dir/List.swift" "$test_dir/invalid.png" 390 fit light en_US
grep -q 'pass a number or screen' "$test_dir/failure.log"
# A fixture that crashes is reported at once, not waited on until the timeout.
cat >"$test_dir/Crash.swift" <<'SWIFT'
import SwiftUI
@MainActor enum PreviewFixture {
    static func makeView() -> some View {
        if CommandLine.arguments.count > 0 { fatalError("Intentional render failure") }
        return EmptyView()
    }
}
SWIFT
expect_failure "$test_dir/Crash.swift" "$test_dir/invalid.png" 200 80 light en_US
grep -q 'The fixture crashed while rendering' "$test_dir/failure.log"
check_cleanup
if xcrun simctl listapps "$device" 2>/dev/null | grep -q 'local\.swiftui-component-preview\.render\.'; then
    printf 'Renderer left an app installed on the simulator\n' >&2
    exit 1
fi

# Gallery: four variants from one launch, displayed in points, counted in pixels.
gallery="$test_dir/path with spaces/gallery.html"
PREVIEW_PLATFORM=ios bash "$skill_dir/scripts/gallery.sh" "$fixture" "$gallery" 200 80 en_US 'Chip' 2>/dev/null
[[ "$(grep -o 'data:image/png;base64,' "$gallery" | wc -l | tr -d ' ')" == 4 ]]
grep -q 'data-scale="2"' "$gallery"
grep -q '<span id="pixels">496 × 336 px</span>' "$gallery"
grep -q 'Viewport 200 × 80 pt</span><span>2× render' "$gallery"
check_cleanup

# Live: build only, flat iOS bundle, then install and launch through the launcher.
app="$test_dir/path with spaces/Chip Preview.app"
expect_live_failure() {
    if PREVIEW_PLATFORM=ios bash "$skill_dir/scripts/live.sh" "$@" >"$test_dir/failure.log" 2>&1; then
        printf 'Expected live failure for arguments: %s\n' "$*" >&2
        exit 1
    fi
}
expect_live_failure "$fixture" "$test_dir/invalid.app" 0 480 en_US
expect_live_failure "$fixture" "$test_dir/invalid.app" 640 480 'en";fatalError()'
expect_live_failure "$test_dir/Broken.swift" "$test_dir/invalid.app" 640 480 en_US
[[ ! -e "$test_dir/invalid.app" ]]
PREVIEW_PLATFORM=ios bash "$skill_dir/scripts/live.sh" "$fixture" "$app" 640 480 fr_FR >/dev/null
expect_live_failure "$fixture" "$app" 640 480 fr_FR
launched_bundle="$(/usr/bin/python3 - "$app" <<'CHECK'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
info = plistlib.loads((app/'Info.plist').read_bytes())
assert info['CFBundleExecutable'] == 'SwiftUIPreview'
assert info['MinimumOSVersion'] == '17.0'
assert info['CFBundleIdentifier'].startswith('local.swiftui-component-preview.live.')
assert plistlib.loads((app/'PreviewConfiguration.plist').read_bytes()) == {'locale': 'fr_FR'}
assert sorted(str(p.relative_to(app)) for p in app.rglob('*') if p.is_file()) == [
    'Info.plist', 'PreviewConfiguration.plist', 'SwiftUIPreview']
print(info['CFBundleIdentifier'])
CHECK
)"
for leftover in "$test_dir/path with spaces"/.swiftui-live.*; do
    [[ ! -e "$leftover" ]] || { printf 'Builder left staging files\n' >&2; exit 1; }
done
# The launcher refuses bundles it did not build.
mkdir "$test_dir/Foreign.app"
/usr/bin/python3 -c "import plistlib,sys; open(sys.argv[1],'wb').write(plistlib.dumps({'CFBundleIdentifier':'com.example.app','CFBundleExecutable':'SwiftUIPreview'}))" "$test_dir/Foreign.app/Info.plist"
if bash "$skill_dir/scripts/ios-launch.sh" "$test_dir/Foreign.app" >/dev/null 2>&1; then
    printf 'Launcher accepted a foreign bundle\n' >&2
    exit 1
fi
bash "$skill_dir/scripts/ios-launch.sh" "$app" >"$test_dir/launch.log"
grep -q "^Launched $launched_bundle on $device " "$test_dir/launch.log"
device_udid="$(sed -n 's/.*(\([0-9A-F-]*\))$/\1/p' "$test_dir/launch.log")"
xcrun simctl listapps "$device_udid" | grep -q "$launched_bundle"
device="$device_udid"
printf 'PASS: Mac Catalyst live build and window size; iOS Simulator renders (fixed, fit, screen, scale, frame, light/dark), UIKit fixture, crash and no-ideal-size errors, gallery, live build and launch on %s; temporary files and renderer apps cleaned up\n' "$PREVIEW_IOS_DEVICE"
