#!/bin/bash

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage: packaging/dmg.sh APP OUTPUT_DMG
EOF
    exit 2
}

(($# == 2)) || usage
app=$1
output=$2
[[ -d "$app" ]] || { echo "app does not exist: $app" >&2; exit 1; }
command -v hdiutil >/dev/null || { echo "hdiutil is required" >&2; exit 1; }

mkdir -p "$(dirname "$output")"
rm -f "$output"
hdiutil create \
    -volname Qaptr \
    -srcfolder "$app" \
    -ov \
    -format UDZO \
    "$output" >/dev/null
hdiutil imageinfo "$output" >/dev/null
printf 'created and verified: %s\n' "$output"
