#!/bin/bash

set -euo pipefail

helper_dir=$(cd "$(dirname "$0")" && pwd)
configuration=${1:-release}
case "$configuration" in
    debug | release) ;;
    *)
        printf 'configuration must be debug or release\n' >&2
        exit 2
        ;;
esac
build_dir="$helper_dir/.build/$configuration"
app_dir="$build_dir/QaptrCaptureSpike.app"

swift build --package-path "$helper_dir" --configuration "$configuration"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
cp "$helper_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$build_dir/QaptrCaptureSpike" "$app_dir/Contents/MacOS/QaptrCaptureSpike"
codesign --force --sign - "$app_dir" >/dev/null

printf '%s\n' "$app_dir"
