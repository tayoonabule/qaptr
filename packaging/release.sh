#!/bin/bash

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage: packaging/release.sh [--dry-run] [--reproducibility-check] [--skip-reproducibility]

The default build uses ad-hoc signing and never contacts Apple. A real release
requires QAPTR_SIGNING_IDENTITY and QAPTR_NOTARY_PROFILE on a release machine.
EOF
    exit 2
}

repo_root=$(cd "$(dirname "$0")/.." && pwd)
packaging_dir="$repo_root/packaging"
build_root="${QAPTR_BUILD_DIR:-$packaging_dir/.build}"
version="${QAPTR_VERSION:-0.1.0}"
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
review_dst="$outer/Contents/Applications/QaptrReview.app"
helper_dst="$review_dst/Contents/Library/LoginItems/QaptrHelper.app"
mkdir -p "$build_root" "$outer/Contents/MacOS" "$outer/Contents/Applications"
rm -rf "$review_dst"
cp -R "$review_src" "$review_dst"
mkdir -p "$(dirname "$helper_dst")"
rm -rf "$helper_dst"
cp -R "$helper_src" "$helper_dst"

cat > "$build_root/QaptrLauncher.swift" <<'EOF'
import AppKit
import Foundation

let reviewApp = Bundle.main.bundleURL
    .appendingPathComponent("Contents", isDirectory: true)
    .appendingPathComponent("Applications", isDirectory: true)
    .appendingPathComponent("QaptrReview.app", isDirectory: true)
let helperApp = reviewApp
    .appendingPathComponent("Contents", isDirectory: true)
    .appendingPathComponent("Library", isDirectory: true)
    .appendingPathComponent("LoginItems", isDirectory: true)
    .appendingPathComponent("QaptrHelper.app", isDirectory: true)

let onboardingCompleted = UserDefaults(suiteName: "com.qaptr.review")?
    .bool(forKey: "com.qaptr.review.onboarding.completed") ?? false
let helperIsRunning = !NSRunningApplication
    .runningApplications(withBundleIdentifier: "com.qaptr.helper")
    .isEmpty

if onboardingCompleted && !helperIsRunning {
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApp.activate(ignoringOtherApps: true)
    if FileManager.default.fileExists(atPath: helperApp.path) {
        let alert = NSAlert()
        alert.messageText = "Start Qaptr capture?"
        alert.informativeText = "Qaptr will start periodic, local screen captures at your configured interval. macOS may still require Screen Recording permission for Qaptr Helper. No provider request is made."
        alert.addButton(withTitle: "Start Capture")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn,
           !NSWorkspace.shared.open(helperApp) {
            fputs("Qaptr could not start the packaged capture helper\n", stderr)
        }
    } else {
        let alert = NSAlert()
        alert.messageText = "Capture is unavailable"
        alert.informativeText = "The packaged Qaptr Helper is missing. Reinstall Qaptr to enable capture."
        alert.runModal()
    }
}

if !NSWorkspace.shared.open(reviewApp) {
    fputs("Qaptr could not open the nested review app\\n", stderr)
    exit(1)
}
EOF
swiftc -O -target arm64-apple-macos14.0 -framework AppKit \
    -o "$outer/Contents/MacOS/Qaptr" "$build_root/QaptrLauncher.swift"

cat > "$outer/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Qaptr</string>
    <key>CFBundleExecutable</key>
    <string>Qaptr</string>
    <key>CFBundleIdentifier</key>
    <string>com.qaptr.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Qaptr</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>$build_version</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
EOF
plutil -lint "$outer/Contents/Info.plist" >/dev/null

sign_mode=(--adhoc)
if [[ -n "${QAPTR_SIGNING_IDENTITY:-}" ]]; then
    sign_mode=(--developer-id "$QAPTR_SIGNING_IDENTITY")
elif [[ "$dry_run" == false ]]; then
    echo "real release mode requires QAPTR_SIGNING_IDENTITY; use --dry-run for ad-hoc validation" >&2
    exit 1
fi
bash "$packaging_dir/sign.sh" "${sign_mode[@]}" "$outer"

# Structural checks stay in this entry point so a successful sign cannot hide a
# misplaced login item or a bundle-identity/resource-seal regression.
[[ -d "$review_dst" ]] || { echo "nested review app missing" >&2; exit 1; }
[[ -d "$helper_dst" ]] || { echo "helper is not nested inside the review app login-item directory" >&2; exit 1; }
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$outer/Contents/Info.plist")" == "com.qaptr.app" ]] || exit 1
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$review_dst/Contents/Info.plist")" == "com.qaptr.review" ]] || exit 1
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$helper_dst/Contents/Info.plist")" == "com.qaptr.helper" ]] || exit 1
[[ "$(plutil -extract LSUIElement raw -o - "$helper_dst/Contents/Info.plist")" == "true" ]] || { echo "helper LSUIElement is not true" >&2; exit 1; }
[[ -x "$outer/Contents/MacOS/Qaptr" ]] || exit 1
[[ -x "$review_dst/Contents/MacOS/QaptrReview" ]] || exit 1
[[ -x "$helper_dst/Contents/MacOS/QaptrHelper" ]] || exit 1
open -Ra "$helper_dst" >/dev/null 2>&1 || { echo "LaunchServices rejected the nested helper app" >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 "$outer" >/dev/null

if [[ "$dry_run" == true ]]; then
    bash "$packaging_dir/notarize.sh" --dry-run "$outer"
else
    bash "$packaging_dir/notarize.sh" "$outer"
fi

dmg="$build_root/Qaptr-$version.dmg"
bash "$packaging_dir/dmg.sh" "$outer" "$dmg"

if [[ "$dry_run" == true ]]; then
    echo "ad-hoc packaging verification complete: $outer"
    echo "credential-blocked: Developer ID notarization, stapling, and Gatekeeper assessment"
else
    spctl --assess --type execute --verbose=4 "$outer"
    echo "Developer ID packaging verification complete: $outer"
fi

if [[ "$reproducibility" == true && "$skip_reproducibility" != 1 ]]; then
    bash "$packaging_dir/reproducibility.sh"
fi

printf '%s\n' "$outer"
