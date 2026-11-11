#!/bin/bash
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../skills/swiftui-component-preview" && pwd -P)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/component-live-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
mkdir "$test_dir/path with spaces"
builder="$skill_dir/scripts/live.sh"
cp "$skill_dir/assets/ExampleFixture.swift" "$test_dir/path with spaces/Fixture.swift"
fixture="$test_dir/path with spaces/Fixture.swift"

expect_failure() {
    if bash "$builder" "$@" >"$test_dir/failure.log" 2>&1; then
        printf 'Expected failure for arguments: %s\n' "$*" >&2
        exit 1
    fi
    [[ ! -e "$test_dir/invalid.app" && ! -L "$test_dir/invalid.app" ]]
}

for width in 0 -1 nan inf 1.5 4097 999999999999999999999; do
    expect_failure "$fixture" "$test_dir/invalid.app" "$width" 480 en_US
done
expect_failure "$fixture" "$test_dir/invalid.app" 640 0 en_US
expect_failure "$fixture" "$test_dir/invalid.app" 640 480 ''
expect_failure "$fixture" "$test_dir/invalid.app" 640 480 'en";fatalError()'
expect_failure "$fixture" "$test_dir/invalid.app" 640 480 en_US --launch
expect_failure "$test_dir/missing.swift" "$test_dir/invalid.app" 640 480 en_US
expect_failure "$fixture" "$test_dir/missing/invalid.app" 640 480 en_US
expect_failure "$fixture" "$test_dir/invalid.png" 640 480 en_US

mkdir "$test_dir/existing.app"
printf 'preserve me' >"$test_dir/existing.app/sentinel"
expect_failure "$fixture" "$test_dir/existing.app" 640 480 en_US
[[ "$(cat "$test_dir/existing.app/sentinel")" == 'preserve me' ]]
printf 'preserve file' >"$test_dir/file.app"
expect_failure "$fixture" "$test_dir/file.app" 640 480 en_US
[[ "$(cat "$test_dir/file.app")" == 'preserve file' ]]
ln -s "$test_dir/missing-target" "$test_dir/link.app"
expect_failure "$fixture" "$test_dir/link.app" 640 480 en_US
[[ -L "$test_dir/link.app" && ! -e "$test_dir/missing-target" ]]

printf 'This is not valid Swift.\n' >"$test_dir/Broken.swift"
expect_failure "$test_dir/Broken.swift" "$test_dir/invalid.app" 640 480 en_US
for leftover in "$test_dir"/.swiftui-live.*; do
    [[ ! -e "$leftover" ]] || { printf 'Builder left staging files\n' >&2; exit 1; }
done

app="$test_dir/path with spaces/SwiftUI Preview.app"
bash "$builder" "$fixture" "$app" 640 480 fr_FR
[[ -x "$app/Contents/MacOS/SwiftUIPreview" ]]
/usr/bin/python3 - "$app" <<'CHECK'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
config = plistlib.loads((app/'Contents/Resources/PreviewConfiguration.plist').read_bytes())
assert info['CFBundleExecutable'] == 'SwiftUIPreview'
assert info['LSMinimumSystemVersion'] == '14.0'
assert info['CFBundleIdentifier'].startswith('local.swiftui-component-preview.')
assert config == {'width':640, 'height':480, 'locale':'fr_FR'}
assert sorted(str(p.relative_to(app)) for p in app.rglob('*') if p.is_file()) == [
    'Contents/Info.plist','Contents/MacOS/SwiftUIPreview','Contents/Resources/PreviewConfiguration.plist']
CHECK
for leftover in "$test_dir"/.swiftui-live.* "$test_dir/path with spaces"/.swiftui-live.*; do
    [[ ! -e "$leftover" ]] || { printf 'Builder left staging files\n' >&2; exit 1; }
done
printf 'PASS: live build, metadata, quoted paths, input rejection, existing-output preservation and failure cleanup verified; app not launched\n'
