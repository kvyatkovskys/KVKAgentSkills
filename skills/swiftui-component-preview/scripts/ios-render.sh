#!/bin/bash
set -euo pipefail

# Renders a fixture inside an iOS Simulator. Two ways to call it:
#   ios-render.sh fixture.swift output.png width|fit|screen height|fit|screen light|dark locale [--frame]
#   ios-render.sh --variants fixture.swift output-directory width|screen height|screen locale
# The second form is for gallery.sh: one build and one launch write all four
# "<theme>-<raw|framed>.png" files plus "size.txt" (content size in points).
# Environment: PREVIEW_IOS_DEVICE (name or UDID), PREVIEW_IOS_SCALE (1-3, default 2),
# PREVIEW_IOS_TIMEOUT (seconds, default 90), PREVIEW_SWIFT_VERSION (5, 6 or auto).

usage() {
    printf 'Usage: %s fixture.swift output.png width|fit|screen height|fit|screen light|dark locale [--frame]\n' "$0" >&2
}
ios_tag=render
fail() { printf '%s: %s\n' "$ios_tag" "$1" >&2; exit 2; }

all_variants=false
if [[ "${1-}" == --variants ]]; then
    all_variants=true
    ios_tag=gallery
    shift
    [[ $# -eq 5 ]] || { usage; exit 2; }
    fixture="$1"; output="$2"; width="$3"; height="$4"; locale="$5"
    variants=(light:raw light:framed dark:raw dark:framed)
else
    if [[ $# -ne 6 && $# -ne 7 ]]; then usage; exit 2; fi
    fixture="$1"; output="$2"; width="$3"; height="$4"; theme="$5"; locale="$6"
    frame=raw
    if [[ $# -eq 7 ]]; then
        [[ "$7" == --frame ]] || fail 'The only optional argument is --frame.'
        frame=framed
    fi
    [[ "$theme" == light || "$theme" == dark ]] || fail 'Appearance must be light or dark.'
    variants=("$theme:$frame")
fi

# Length is bounded before numeric comparison, including on Bash 3.2.
for dimension in "$width" "$height"; do
    [[ "$dimension" == screen ]] && continue
    [[ "$dimension" == fit && "$all_variants" == false ]] && continue
    [[ "$dimension" =~ ^[1-9][0-9]{0,3}$ ]] || fail 'Dimensions must be integers from 1 to 4096, fit, or screen.'
    (( dimension <= 4096 )) || fail 'Dimensions must be integers from 1 to 4096, fit, or screen.'
done
if [[ "$width" == screen || "$height" == screen ]]; then
    [[ "$width" == "$height" ]] || fail 'screen covers the whole device: pass it for both width and height.'
fi
scale="${PREVIEW_IOS_SCALE:-2}"
[[ "$scale" =~ ^[1-3]$ ]] || fail 'PREVIEW_IOS_SCALE must be 1, 2, or 3.'
timeout="${PREVIEW_IOS_TIMEOUT:-90}"
[[ "$timeout" =~ ^[1-9][0-9]{0,3}$ ]] || fail 'PREVIEW_IOS_TIMEOUT must be a whole number of seconds.'
[[ ${#locale} -le 128 && "$locale" =~ ^[A-Za-z][A-Za-z0-9_@=.-]*$ ]] || fail 'Supply a locale identifier such as en_US or de-DE.'
[[ -f "$fixture" && -r "$fixture" && "$fixture" == *.swift ]] || fail 'Fixture must be a readable .swift file.'
if [[ "$all_variants" == true ]]; then
    [[ -d "$output" && ! -L "$output" ]] || fail 'Output directory must already exist.'
    output="$(cd "$output" && pwd -P)"
else
    [[ "$output" == *.png || "$output" == *.PNG ]] || fail 'Output must have a .png extension.'
    [[ -d "$(dirname "$output")" ]] || fail 'Output parent directory must already exist.'
    [[ ! -d "$output" && ! -L "$output" ]] || fail 'Output must be a regular path, not a directory or symlink.'
    output="$(cd "$(dirname "$output")" && pwd -P)/$(basename "$output")"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=ios-common.sh
source "$script_dir/ios-common.sh"
ios_require_tools

fixture="$(cd "$(dirname "$fixture")" && pwd -P)/$(basename "$fixture")"
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/swiftui-component-preview.XXXXXX")"
temp_dir="$(cd "$temp_dir" && pwd -P)"
bundle_id="local.swiftui-component-preview.render.$(basename "$temp_dir" | tr -c 'A-Za-z0-9\n' '-')"
installed=false
staged=''
cleanup() {
    if [[ "$installed" == true ]]; then
        xcrun simctl terminate "$ios_udid" "$bundle_id" >/dev/null 2>&1 || true
        xcrun simctl uninstall "$ios_udid" "$bundle_id" >/dev/null 2>&1 || true
    fi
    [[ -z "$staged" ]] || rm -f "$staged"
    rm -rf "$temp_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

app="$temp_dir/Preview.app"
mkdir -p "$app" "$temp_dir/out"
ios_write_info "$app" "$bundle_id"
# The supplied Swift is executable code; it runs in the simulator with the caller's file access.
ios_compile "$script_dir/IOSRenderer.swift" "$fixture" "$app" "$temp_dir/module-cache"

ios_select_device
ios_boot_device
xcrun simctl install "$ios_udid" "$app" || fail "Could not install the renderer on $ios_device."
installed=true
launch="$(xcrun simctl launch "$ios_udid" "$bundle_id" "$temp_dir/out" "$width" "$height" "$locale" "$scale" "${variants[@]}")" \
    || fail "Could not launch the renderer on $ios_device."
# Simulator apps are host processes, so a crash shows as the process disappearing.
pid="${launch##*: }"
[[ "$pid" =~ ^[0-9]+$ ]] || pid=''

# The app writes status.txt last; a fixture that crashes or hangs never does.
status="$temp_dir/out/status.txt"
deadline=$(( SECONDS + timeout ))
while [[ ! -f "$status" ]]; do
    (( SECONDS < deadline )) || fail "No render after ${timeout}s on $ios_device: the fixture never finished laying out."
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
        sleep 0.2
        [[ -f "$status" ]] || fail "The fixture crashed while rendering on $ios_device."
    fi
    sleep 0.2
done
if ! grep -q '^ok$' "$status"; then
    if grep -q 'contentHasNoFittingSize' "$status"; then
        fail 'The fixture has no ideal size on a fitted axis (lists, forms and scroll views collapse on iOS); pass a number or screen.'
    fi
    fail "$(sed -n 's/^error: //p' "$status" | head -n 1)"
fi
fitted="$(sed -n 's/^fitted //p' "$status")"
[[ -z "$fitted" ]] || printf 'render: fitted content size %s\n' "$fitted" >&2
size="$(sed -n 's/^size //p' "$status")"
printf '%s: %s, content %s pt at %sx\n' "$ios_tag" "$ios_device" "$size" "$scale" >&2

if [[ "$all_variants" == true ]]; then
    for variant in "${variants[@]}"; do
        name="${variant/:/-}.png"
        [[ -s "$temp_dir/out/$name" ]] || fail "The renderer did not produce $name."
        cp "$temp_dir/out/$name" "$output/$name"
    done
    printf '%s\n' "$size" >"$output/size.txt"
else
    rendered="$temp_dir/out/${variants[0]/:/-}.png"
    [[ -s "$rendered" ]] || fail 'The renderer did not produce an image.'
    # Replace the output atomically, from a file in the same directory.
    staged="$(mktemp "$(dirname "$output")/.swiftui-render.XXXXXX")"
    cp "$rendered" "$staged"
    chmod 644 "$staged"
    mv -f "$staged" "$output"
    staged=''
    printf '%s\n' "$output"
fi
