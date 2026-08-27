#!/bin/bash

set -euo pipefail

app_root=$(cd "$(dirname "$0")" && pwd)
configuration=${1:-release}

case "$configuration" in
  debug | release) ;;
  *)
    printf 'configuration must be debug or release\n' >&2
    exit 2
    ;;
esac

swift build --package-path "$app_root" --configuration "$configuration"
bin_path=$(swift build --package-path "$app_root" --configuration "$configuration" --show-bin-path)
binary="$bin_path/Qaptr"
bundle="$bin_path/Qaptr.app"

[[ -x "$binary" ]] || { printf 'Swift build did not produce %s\n' "$binary" >&2; exit 1; }

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$app_root/Resources/Info.plist" "$bundle/Contents/Info.plist"
cp "$binary" "$bundle/Contents/MacOS/Qaptr"
codesign --force --sign - "$bundle" >/dev/null

printf '%s\n' "$bundle"
