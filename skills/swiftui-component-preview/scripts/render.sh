#!/bin/bash
set -euo pipefail

usage() {
    printf 'Usage: %s fixture.swift output.png width|fit height|fit light|dark locale [--frame]\n' "$0" >&2
}
fail() { printf 'render: %s\n' "$1" >&2; exit 2; }

if [[ $# -ne 6 && $# -ne 7 ]]; then usage; exit 2; fi
fixture="$1"
output="$2"
width="$3"
height="$4"
theme="$5"
locale="$6"
framed=false
if [[ $# -eq 7 ]]; then
    [[ "$7" == --frame ]] || fail 'The only optional argument is --frame.'
    framed=true
fi

# Length is bounded before numeric comparison, including on Bash 3.2.
for dimension in "$width" "$height"; do
    [[ "$dimension" == fit ]] && continue
    [[ "$dimension" =~ ^[1-9][0-9]{0,3}$ ]] || fail 'Dimensions must be integers from 1 to 4096, or fit.'
    (( dimension <= 4096 )) || fail 'Dimensions must be integers from 1 to 4096, or fit.'
done
[[ "$theme" == light || "$theme" == dark ]] || fail 'Appearance must be light or dark.'
[[ ${#locale} -le 128 && "$locale" =~ ^[A-Za-z][A-Za-z0-9_@=.-]*$ ]] || fail 'Supply a locale identifier such as en_US or de-DE.'
[[ -f "$fixture" && -r "$fixture" && "$fixture" == *.swift ]] || fail 'Fixture must be a readable .swift file.'
[[ "$output" == *.png || "$output" == *.PNG ]] || fail 'Output must have a .png extension.'
[[ -d "$(dirname "$output")" ]] || fail 'Output parent directory must already exist.'
[[ ! -d "$output" && ! -L "$output" ]] || fail 'Output must be a regular path, not a directory or symlink.'
[[ "$(uname -s)" == Darwin ]] || fail 'Rendering requires macOS and the Xcode command-line tools.'
command -v xcrun >/dev/null 2>&1 || fail 'Install the Xcode command-line tools to obtain swiftc.'

fixture="$(cd "$(dirname "$fixture")" && pwd -P)/$(basename "$fixture")"
output="$(cd "$(dirname "$output")" && pwd -P)/$(basename "$output")"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/swiftui-component-preview.XXXXXX")"
trap 'rm -rf "$temp_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

# Language mode: Swift 6 with strict concurrency when the compiler has it, else Swift 5.
# PREVIEW_SWIFT_VERSION=5 compiles fixtures adapted from Swift 5 projects without strict checks.
swift_mode="${PREVIEW_SWIFT_VERSION:-auto}"
if [[ "$swift_mode" == auto ]]; then
    if xcrun swiftc -version 2>&1 | grep -Eq 'Swift version ([6-9]|[1-9][0-9])\.'; then swift_mode=6; else swift_mode=5; fi
fi
[[ "$swift_mode" == 5 || "$swift_mode" == 6 ]] || fail 'PREVIEW_SWIFT_VERSION must be 5, 6, or auto.'
swift_flags=(-swift-version "$swift_mode")
if [[ "$swift_mode" == 6 ]]; then swift_flags+=(-strict-concurrency=complete); fi

# The supplied Swift is executable code, with the caller's normal permissions.
xcrun swiftc "${swift_flags[@]}" -parse-as-library \
    -target "$(uname -m)-apple-macosx14.0" \
    -module-cache-path "$temp_dir/module-cache" \
    "$script_dir/ComponentRenderer.swift" "$fixture" -o "$temp_dir/render"
"$temp_dir/render" "$output" "$width" "$height" "$theme" "$locale" "$framed"
