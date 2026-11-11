#!/bin/bash
# Runs every check for swiftui-component-preview. Rendering checks need macOS and Xcode.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
python3 bootstrap.py
if [[ "$(uname -s)" != Darwin ]]; then
    printf 'SKIP: rendering, gallery, live and refresh checks require macOS.\n'
    exit 0
fi
bash smoke.sh
python3 gallery.py
bash live.sh
python3 bootstrap_render.py
python3 refresh.py
