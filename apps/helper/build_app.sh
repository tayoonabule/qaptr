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
rust_target="$helper_dir/.build/rust"
app_dir="$build_dir/QaptrHelper.app"

cargo build \
    --manifest-path "$helper_dir/../../crates/qaptr-ffi/Cargo.toml" \
    --release \
    --target-dir "$rust_target"

QAPTR_FFI_LIBRARY_DIR="$rust_target/release" \
    swift build --package-path "$helper_dir" --configuration "$configuration"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Frameworks"
cp "$helper_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$build_dir/QaptrHelper" "$app_dir/Contents/MacOS/QaptrHelper"
ffi_name="libqaptr_ffi.dylib"
cp "$rust_target/release/$ffi_name" "$app_dir/Contents/Frameworks/$ffi_name"

signing_identity="${QAPTR_CODESIGN_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
    signing_identity=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
        | head -n 1)
fi

if [[ -n "$signing_identity" ]]; then
    codesign --force --sign "$signing_identity" "$app_dir/Contents/Frameworks/$ffi_name" >/dev/null
    codesign --force --sign "$signing_identity" "$app_dir" >/dev/null
else
    codesign --force --sign - "$app_dir" >/dev/null
fi

printf '%s\n' "$app_dir"
