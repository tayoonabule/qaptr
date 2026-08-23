#!/bin/bash

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage: packaging/release.sh [--dry-run] [--reproducibility-check] [--skip-reproducibility]

The default build uses ad-hoc signing for structural validation only. Install
local builds with a stable Apple Development identity via
QAPTR_SIGNING_IDENTITY. A distributed release additionally requires
QAPTR_NOTARY_PROFILE on a release machine.
EOF
    exit 2
}

repo_root=$(cd "$(dirname "$0")/.." && pwd)
packaging_dir="$repo_root/packaging"
build_root="${QAPTR_BUILD_DIR:-$packaging_dir/.build}"
# Derive the default version from the workspace manifest rather than repeating
# it here. A hardcoded default silently drifts from Cargo.toml, and the two are
# the same product version, so the manifest is the single source. An explicit
# QAPTR_VERSION still wins, which is what the reproducibility comparison and any
# one-off build rely on.
workspace_version=$(awk '
    /^\[workspace\.package\]/ { in_section = 1; next }
    /^\[/ { in_section = 0 }
    in_section && /^version[[:space:]]*=/ {
        gsub(/^version[[:space:]]*=[[:space:]]*"|"[[:space:]]*$/, "")
        print
        exit
    }
' "$repo_root/Cargo.toml")
[[ -n "$workspace_version" ]] || {
    echo "could not read version from [workspace.package] in Cargo.toml" >&2
    exit 1
}
version="${QAPTR_VERSION:-$workspace_version}"
build_version="${QAPTR_BUILD_VERSION:-1}"
dry_run=false
reproducibility=false
skip_reproducibility="${QAPTR_SKIP_REPRODUCIBILITY:-0}"

while (($# > 0)); do
    case "$1" in
        --dry-run)
            dry_run=true
            shift
            ;;
        --reproducibility-check)
            reproducibility=true
            shift
            ;;
        --skip-reproducibility)
            skip_reproducibility=1
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            usage
            ;;
    esac
done

# Reproducibility is intentionally credential-free. When no Developer ID
# identity is supplied, run the package itself in the same ad-hoc mode used by
# the clean-checkout comparisons below. A real identity still exercises the
# release signing path before the comparison.
if [[ "$reproducibility" == true && -z "${QAPTR_SIGNING_IDENTITY:-}" ]]; then
    dry_run=true
fi

[[ "$(uname -s)" == "Darwin" ]] || { echo "U22 packaging requires macOS" >&2; exit 1; }
[[ "$(uname -m)" == "arm64" ]] || { echo "U22 v1 packaging requires Apple silicon (arm64)" >&2; exit 1; }
for tool in codesign plutil otool nm file swiftc hdiutil; do
    command -v "$tool" >/dev/null || { echo "required tool is missing: $tool" >&2; exit 1; }
done

build_product_app() {
    local app_var=$1
    local build_script=$2
    local expected=$3
    local value=${!app_var:-}
    if [[ -n "$value" ]]; then
        [[ -d "$value" ]] || { echo "$app_var does not exist: $value" >&2; exit 1; }
        printf '%s\n' "$value"
        return
    fi
    if [[ -x "$build_script" ]]; then
        if ! bash "$build_script" release >/dev/null; then
            echo "product build failed: $build_script" >&2
            exit 1
        fi
    else
        echo "missing product build script: $build_script" >&2
        exit 1
    fi
    [[ -d "$expected" ]] || { echo "build script did not produce: $expected" >&2; exit 1; }
    printf '%s\n' "$expected"
}

helper_src=$(build_product_app QAPTR_HELPER_APP "$repo_root/apps/helper/build_app.sh" "$repo_root/apps/helper/.build/release/QaptrHelper.app")
review_src=$(build_product_app QAPTR_REVIEW_APP "$repo_root/apps/review/build_app.sh" "$repo_root/apps/review/.build/release/QaptrReview.app")

outer="$build_root/Qaptr.app"
review_dst="$outer"
helper_dst="$outer/Contents/Library/LoginItems/QaptrHelper.app"
mkdir -p "$build_root"
rm -rf "$outer"
cp -R "$review_src" "$outer"
mkdir -p "$(dirname "$helper_dst")"
rm -rf "$helper_dst"
cp -R "$helper_src" "$helper_dst"

# The installed product is one user-facing app. The standalone SwiftPM review
# target keeps its QaptrReview name for local development, but the packaged
# copy is promoted to the top-level Qaptr.app so LaunchServices, Finder, TCC,
# and the running UI all agree on one application identity.
mv "$outer/Contents/MacOS/QaptrReview" "$outer/Contents/MacOS/Qaptr"
plutil -replace CFBundleDisplayName -string "Qaptr" "$outer/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "Qaptr" "$outer/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "com.qaptr.app" "$outer/Contents/Info.plist"
plutil -replace CFBundleName -string "Qaptr" "$outer/Contents/Info.plist"

# One release has one version across all three application bundles. Keeping the
# nested apps in lockstep also lets LaunchServices prefer an actual upgrade
# instead of retaining several equal-version candidates.
for nested_app in "$review_dst" "$helper_dst"; do
    plutil -replace CFBundleShortVersionString -string "$version" "$nested_app/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "$build_version" "$nested_app/Contents/Info.plist"
done

plutil -lint "$outer/Contents/Info.plist" >/dev/null

sign_mode=(--adhoc)
signing_description="ad-hoc structural"
if [[ -n "${QAPTR_SIGNING_IDENTITY:-}" ]]; then
    sign_mode=(--identity "$QAPTR_SIGNING_IDENTITY")
    signing_description="identity-signed"
elif [[ "$dry_run" == false ]]; then
    echo "real release mode requires QAPTR_SIGNING_IDENTITY; use --dry-run for ad-hoc validation" >&2
    exit 1
fi
bash "$packaging_dir/sign.sh" "${sign_mode[@]}" "$outer"

# Structural checks stay in this entry point so a successful sign cannot hide a
# misplaced login item or a bundle-identity/resource-seal regression.
[[ -d "$helper_dst" ]] || { echo "helper is not nested inside the review app login-item directory" >&2; exit 1; }
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$outer/Contents/Info.plist")" == "com.qaptr.app" ]] || exit 1
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$helper_dst/Contents/Info.plist")" == "com.qaptr.helper" ]] || exit 1
[[ "$(plutil -extract LSUIElement raw -o - "$helper_dst/Contents/Info.plist")" == "true" ]] || { echo "helper LSUIElement is not true" >&2; exit 1; }
[[ -x "$outer/Contents/MacOS/Qaptr" ]] || exit 1
[[ -x "$helper_dst/Contents/MacOS/QaptrHelper" ]] || exit 1
[[ -f "$review_dst/Contents/Resources/QaptrAperture.svg" ]] || {
    echo "nested review app logo resource is missing" >&2
    exit 1
}
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$helper_dst/Contents/Info.plist")" == "$version" ]] || exit 1
[[ "$(plutil -extract CFBundleVersion raw -o - "$helper_dst/Contents/Info.plist")" == "$build_version" ]] || exit 1
codesign --verify --deep --strict --verbose=2 "$outer" >/dev/null

if [[ "$dry_run" == true ]]; then
    bash "$packaging_dir/notarize.sh" --dry-run "$outer"
else
    bash "$packaging_dir/notarize.sh" "$outer"
fi

dmg="$build_root/Qaptr-$version.dmg"
bash "$packaging_dir/dmg.sh" "$outer" "$dmg"

if [[ "$dry_run" == true ]]; then
    echo "$signing_description packaging verification complete: $outer"
    echo "release-blocked: Developer ID notarization, stapling, and Gatekeeper assessment"
else
    spctl --assess --type execute --verbose=4 "$outer"
    echo "Developer ID packaging verification complete: $outer"
fi

if [[ "$reproducibility" == true && "$skip_reproducibility" != 1 ]]; then
    bash "$packaging_dir/reproducibility.sh"
fi

printf '%s\n' "$outer"
