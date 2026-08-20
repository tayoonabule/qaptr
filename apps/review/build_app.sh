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
swift_resource_bundle="$swift_bin_path/QaptrReview_QaptrReview.bundle"
[[ -x "$swift_binary" ]] || { echo "Swift build did not produce: $swift_binary" >&2; exit 1; }
[[ -d "$swift_resource_bundle" ]] || {
    echo "Swift build did not produce resources: $swift_resource_bundle" >&2
    exit 1
}

# Keep the raw SwiftPM executable runnable during development. ReviewBridge
# searches beside the executable after the package-specific environment and
# bundle paths, so `swift run`/the .build executable use the same bridge as the
# packaged app without weakening the fail-closed loader.
ln -sf "$ffi_library" "$swift_bin_path/libqaptr_review_ffi.dylib"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Frameworks"
mkdir -p "$app_dir/Contents/Resources"
cp "$review_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$swift_binary" "$app_dir/Contents/MacOS/QaptrReview"
# Put runtime assets in the standard signed app-resource location. The view
# checks Bundle.main first and only uses SwiftPM's generated bundle in local
# `swift run` builds.
cp "$swift_resource_bundle/QaptrAperture.svg" "$app_dir/Contents/Resources/QaptrAperture.svg"
ffi_name=$(basename "$ffi_library")
cp "$ffi_library" "$app_dir/Contents/Frameworks/$ffi_name"
# Cargo embeds the build-machine path as the dylib install name. Rewrite it
# before packaging so the nested review app never depends on the source tree.
install_name_tool -id "@rpath/$ffi_name" "$app_dir/Contents/Frameworks/$ffi_name"
install_name_tool -add_rpath "@loader_path/../Frameworks" "$app_dir/Contents/MacOS/QaptrReview" 2>/dev/null || true

# Ad-hoc signatures identify the exact binary hash. That makes Keychain ask for
# permission again after every rebuild. Prefer the user's stable Apple
# Development identity when one is available, while keeping ad-hoc signing as
# a fallback for CI and machines without a local certificate.
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
