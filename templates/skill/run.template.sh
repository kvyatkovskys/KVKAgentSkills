#!/bin/bash
# Runs every check for {{name}}. Keep it runnable from any directory.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
printf 'No tests for {{name}} yet: replace this stub in tests/{{name}}/run.sh.\n' >&2
exit 1
