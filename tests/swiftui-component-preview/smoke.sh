#!/bin/bash
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../skills/swiftui-component-preview" && pwd -P)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/component-preview-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/path with spaces"
mkdir -p "$test_dir/compiler-temporary-files"
export TMPDIR="$test_dir/compiler-temporary-files"
cp "$skill_dir/assets/ExampleFixture.swift" "$test_dir/path with spaces/Fixture.swift"
fixture="$test_dir/path with spaces/Fixture.swift"
renderer="$skill_dir/scripts/render.sh"

expect_failure() {
    if bash "$renderer" "$@" >"$test_dir/failure.log" 2>&1; then
        printf 'Expected failure for arguments: %s\n' "$*" >&2
        exit 1
    fi
    if [[ -e "$test_dir/invalid.png" ]]; then
        printf 'Invalid input produced an output file\n' >&2
        exit 1
    fi
}

for width in 0 -1 nan inf 1.5 4097 999999999999999999999; do
    expect_failure "$fixture" "$test_dir/invalid.png" "$width" 320 light en_US
done
expect_failure "$fixture" "$test_dir/invalid.png" 480 0 light en_US
expect_failure "$fixture" "$test_dir/invalid.png" 480 320 sepia en_US
expect_failure "$fixture" "$test_dir/invalid.png" 480 320 light ''
expect_failure "$fixture" "$test_dir/invalid.png" 480 320 light en_US --unknown
expect_failure "$test_dir/missing.swift" "$test_dir/invalid.png" 480 320 light en_US
expect_failure "$fixture" "$test_dir/missing/invalid.png" 480 320 light en_US
expect_failure "$fixture" "$test_dir/invalid.jpg" 480 320 light en_US
ln -s "$test_dir/target.png" "$test_dir/invalid.png"
if bash "$renderer" "$fixture" "$test_dir/invalid.png" 480 320 light en_US >"$test_dir/failure.log" 2>&1; then
    printf 'Expected symlink output rejection\n' >&2
    exit 1
fi
rm "$test_dir/invalid.png"

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
    for leftover in "$TMPDIR"/swiftui-component-preview.*; do
        [[ ! -e "$leftover" ]] || { printf 'Renderer left temporary files\n' >&2; exit 1; }
    done
}

printf 'This is not valid Swift.\n' >"$test_dir/Broken.swift"
expect_failure "$test_dir/Broken.swift" "$test_dir/invalid.png" 480 320 light en_US
check_cleanup

bash "$renderer" "$fixture" "$test_dir/path with spaces/light.png" 480 320 light en_US
check_png "$test_dir/path with spaces/light.png" 480 320
check_cleanup
bash "$renderer" "$fixture" "$test_dir/dark.png" 480 320 dark en_US
check_png "$test_dir/dark.png" 480 320
check_cleanup
if cmp -s "$test_dir/path with spaces/light.png" "$test_dir/dark.png"; then
    printf 'Light and dark images unexpectedly match\n' >&2
    exit 1
fi
bash "$renderer" "$fixture" "$test_dir/framed.png" 480 320 light en_US --frame
check_png "$test_dir/framed.png" 528 408
check_cleanup
bash "$renderer" "$fixture" "$test_dir/fit-height.png" 390 fit light en_US 2>"$test_dir/fit.log"
grep -q '^render: fitted content size 390x[0-9]*$' "$test_dir/fit.log"
fitted_height="$(sed -n 's/^render: fitted content size 390x//p' "$test_dir/fit.log")"
check_png "$test_dir/fit-height.png" 390 "$fitted_height"
bash "$renderer" "$fixture" "$test_dir/fit-both.png" fit fit dark en_US 2>"$test_dir/fit.log"
fitted="$(sed -n 's/^render: fitted content size //p' "$test_dir/fit.log")"
check_png "$test_dir/fit-both.png" "${fitted%x*}" "${fitted#*x}"
(( ${fitted%x*} > 1 && ${fitted#*x} > 1 ))
check_cleanup
printf 'PASS: invalid input and compiler failures rejected; light, dark, spaced paths, framed dimensions, fitted sizes, and temporary cleanup verified\n'
