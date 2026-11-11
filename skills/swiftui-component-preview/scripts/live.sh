#!/bin/bash
set -euo pipefail

usage() { printf 'Usage: %s fixture.swift output.app width height locale\n' "$0" >&2; }
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
[[ "$(uname -s)" == Darwin ]] || fail 'Live preview builds require macOS and Xcode command-line tools.'
command -v xcrun >/dev/null 2>&1 || fail 'Install the Xcode command-line tools to obtain swiftc.'
command -v python3 >/dev/null 2>&1 || fail 'Live preview builds require Python 3.8 or later (standard library only).'
fixture="$(cd "$(dirname "$fixture")" && pwd -P)/$(basename "$fixture")"
output_parent="$(cd "$(dirname "$output")" && pwd -P)"
output="$output_parent/$(basename "$output")"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
stage_dir="$(mktemp -d "$output_parent/.swiftui-live.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
app="$stage_dir/Preview.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

# Pass validated values as data, never as generated Swift source.
python3 - "$app" "$width" "$height" "$locale" <<'PY'
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
    'LSMinimumSystemVersion': '14.0',
    'NSHighResolutionCapable': True,
}
config = {'width': int(sys.argv[2]), 'height': int(sys.argv[3]), 'locale': sys.argv[4]}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
(app/'Contents/Resources/PreviewConfiguration.plist').write_bytes(plistlib.dumps(config))
PY

# Build only: the host and trusted fixture are the complete source list.
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
    -target "$(uname -m)-apple-macosx14.0" \
    -module-cache-path "$stage_dir/module-cache" \
    "$script_dir/LiveHost.swift" "$fixture" -o "$app/Contents/MacOS/SwiftUIPreview"

# Darwin's exclusive rename installs atomically without replacing a raced-in path.
python3 - "$app" "$output" <<'PY'
import ctypes, os, sys
libc = ctypes.CDLL(None, use_errno=True)
rename = libc.renamex_np
rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
rename.restype = ctypes.c_int
if rename(os.fsencode(sys.argv[1]), os.fsencode(sys.argv[2]), 4) != 0:  # RENAME_EXCL
    error = ctypes.get_errno()
    raise OSError(error, os.strerror(error), sys.argv[2])
PY
printf 'Built live preview (not launched): %s\n' "$output"
