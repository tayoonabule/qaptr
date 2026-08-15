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
ffi_library="$rust_target/release/libqaptr_review_ffi.dylib"

cargo build \
    --manifest-path "$review_dir/../../crates/qaptr-review-ffi/Cargo.toml" \
    --release \
    --target-dir "$rust_target"

QAPTR_REVIEW_FFI_LIBRARY_PATH="$ffi_library" \
    swift build --package-path "$review_dir" --configuration "$configuration"

swift_bin_path=$(swift build \
    --package-path "$review_dir" \
    --configuration "$configuration" \
    --show-bin-path)
swift_binary="$swift_bin_path/QaptrReview"
[[ -x "$swift_binary" ]] || { echo "Swift build did not produce: $swift_binary" >&2; exit 1; }

# Keep the raw SwiftPM executable runnable during development. ReviewBridge
# searches beside the executable after the package-specific environment and
# bundle paths, so `swift run`/the .build executable use the same bridge as the
# packaged app without weakening the fail-closed loader.
ln -sf "$ffi_library" "$swift_bin_path/libqaptr_review_ffi.dylib"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Frameworks"
cp "$review_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$swift_binary" "$app_dir/Contents/MacOS/QaptrReview"
ffi_name=$(basename "$ffi_library")
cp "$ffi_library" "$app_dir/Contents/Frameworks/$ffi_name"
codesign --force --sign - "$app_dir" >/dev/null

validate_load() {
    local library=$1
    swift - "$library" <<'SWIFT'
import Darwin

let path = CommandLine.arguments[1]
guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
    fputs("could not load \(path)\n", stderr)
    exit(1)
}
dlclose(handle)
SWIFT
}

validate_load "$swift_bin_path/libqaptr_review_ffi.dylib"
validate_load "$app_dir/Contents/Frameworks/libqaptr_review_ffi.dylib"

printf '%s\n' "$app_dir"
