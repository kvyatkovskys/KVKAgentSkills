#!/bin/bash
# Validates the repository, then runs tests/<skill>/run.sh for every skill.
# Usage: tests/run-all.sh [skill-name ...]
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
failed=()
python3 "$root/tools/validate.py" || failed+=("validate")
if [[ $# -gt 0 ]]; then skills=("$@"); else
    skills=()
    for directory in "$root"/skills/*/; do skills+=("$(basename "$directory")"); done
fi
for skill in "${skills[@]}"; do
    printf '\n== %s ==\n' "$skill"
    runner="$root/tests/$skill/run.sh"
    if [[ ! -f "$runner" ]]; then
        printf 'Missing %s\n' "$runner" >&2
        failed+=("$skill")
    elif ! bash "$runner"; then
        failed+=("$skill")
    fi
done
if [[ ${#failed[@]} -gt 0 ]]; then
    printf '\nFAILED: %s\n' "${failed[*]}" >&2
    exit 1
fi
printf '\nAll checks passed.\n'
