#!/bin/bash

set -euo pipefail

review_dir=$(cd "$(dirname "$0")" && pwd)
configuration=${1:-release}
case "$configuration" in
    debug | release) ;;
    *)
        printf 'configuration must be debug or release\n' >&2
        exit 2
        ;;
esac
build_dir="$review_dir/.build/$configuration"
rust_target="$review_dir/.build/rust"
app_dir="$build_dir/QaptrReview.app"

cargo build \
    --manifest-path "$review_dir/../../crates/qaptr-review-ffi/Cargo.toml" \
    --release \
    --target-dir "$rust_target"

QAPTR_REVIEW_FFI_LIBRARY_DIR="$rust_target/release" \
    swift build --package-path "$review_dir" --configuration "$configuration"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Frameworks"
cp "$review_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$build_dir/QaptrReview" "$app_dir/Contents/MacOS/QaptrReview"
cp "$rust_target/release/libqaptr_review_ffi.dylib" "$app_dir/Contents/Frameworks/libqaptr_review_ffi.dylib"
codesign --force --sign - "$app_dir" >/dev/null

printf '%s\n' "$app_dir"
