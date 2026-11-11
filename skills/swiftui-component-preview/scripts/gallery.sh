#!/bin/bash
set -euo pipefail

usage() {
    printf 'Usage: %s fixture.swift output.html width height locale [title]\n' "$0" >&2
}
fail() { printf 'gallery: %s\n' "$1" >&2; exit 2; }

if [[ $# -ne 5 && $# -ne 6 ]]; then usage; exit 2; fi
fixture="$1"
output="$2"
width="$3"
height="$4"
locale="$5"
title="${6-SwiftUI component}"
for dimension in "$width" "$height"; do
    [[ "$dimension" =~ ^[1-9][0-9]{0,3}$ ]] || fail 'Dimensions must be integers from 1 to 4096.'
    (( dimension <= 4096 )) || fail 'Dimensions must be integers from 1 to 4096.'
done
[[ ${#locale} -le 128 && "$locale" =~ ^[A-Za-z][A-Za-z0-9_@=.-]*$ ]] || fail 'Supply a locale identifier such as en_US or de-DE.'
[[ -f "$fixture" && -r "$fixture" && "$fixture" == *.swift ]] || fail 'Fixture must be a readable .swift file.'
[[ "$output" == *.html || "$output" == *.HTML ]] || fail 'Output must have a .html extension.'
[[ -d "$(dirname "$output")" ]] || fail 'Output parent directory must already exist.'
[[ ! -e "$output" || -f "$output" ]] || fail 'Output must be a regular path.'
[[ ! -L "$output" ]] || fail 'Output must not be a symlink.'
[[ ! "$fixture" -ef "$output" ]] || fail 'Output must not overwrite the fixture.'
[[ "$(uname -s)" == Darwin ]] || fail 'Rendering requires macOS and the Xcode command-line tools.'
command -v xcrun >/dev/null 2>&1 || fail 'Install the Xcode command-line tools to obtain swiftc.'
command -v python3 >/dev/null 2>&1 || fail 'Gallery generation requires Python 3.'

fixture="$(cd "$(dirname "$fixture")" && pwd -P)/$(basename "$fixture")"
output="$(cd "$(dirname "$output")" && pwd -P)/$(basename "$output")"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/swiftui-component-gallery.XXXXXX")"
trap 'rm -rf "$temp_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

# Compile trusted fixture code once; each process renders a fresh, deterministic state.
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
    -target "$(uname -m)-apple-macosx14.0" \
    -module-cache-path "$temp_dir/module-cache" \
    "$script_dir/ComponentRenderer.swift" "$fixture" -o "$temp_dir/render"
for theme in light dark; do
    for frame in raw framed; do
        framed=false
        if [[ "$frame" == framed ]]; then framed=true; fi
        "$temp_dir/render" "$temp_dir/$theme-$frame.png" "$width" "$height" "$theme" "$locale" "$framed" >/dev/null
    done
done
python3 "$script_dir/gallery_html.py" "$temp_dir" "$output" "$width" "$height" "$locale" "$title" "$fixture"
