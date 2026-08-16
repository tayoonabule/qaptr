#!/bin/bash

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage: packaging/sign.sh [--adhoc | --developer-id IDENTITY] APP

Ad-hoc signing is the safe local default. Developer ID signing is only for a
release machine that already has the requested identity installed.
EOF
    exit 2
}

root_dir=$(cd "$(dirname "$0")/.." && pwd)
entitlements="$root_dir/packaging/signing/entitlements.plist"
identity="-"
timestamp="none"
app=""

while (($# > 0)); do
    case "$1" in
        --adhoc)
            identity="-"
            timestamp="none"
            shift
            ;;
        --developer-id)
            (($# >= 2)) || usage
            identity="$2"
            timestamp="required"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        -* )
            usage
            ;;
        *)
            [[ -z "$app" ]] || usage
            app="$1"
            shift
            ;;
    esac
done

[[ -n "$app" && -d "$app" ]] || usage
[[ -f "$entitlements" ]] || { echo "missing entitlements: $entitlements" >&2; exit 1; }
command -v codesign >/dev/null || { echo "codesign is required" >&2; exit 1; }
command -v plutil >/dev/null || { echo "plutil is required" >&2; exit 1; }
command -v otool >/dev/null || { echo "otool is required" >&2; exit 1; }
command -v nm >/dev/null || { echo "nm is required" >&2; exit 1; }

plist_value() {
    local key=$1
    local bundle=$2
    plutil -extract "$key" raw -o - "$bundle/Contents/Info.plist"
}

bundle_id() {
    plist_value CFBundleIdentifier "$1"
}

bundle_executable() {
    local bundle=$1
    local executable
    executable=$(plist_value CFBundleExecutable "$bundle")
    [[ -x "$bundle/Contents/MacOS/$executable" ]] || {
        echo "missing executable for $bundle: $executable" >&2
        exit 1
    }
    printf '%s\n' "$bundle/Contents/MacOS/$executable"
}

# Hardened runtime turns on library validation. An ad-hoc signature carries no
# Team ID, so a hardened ad-hoc app refuses to load its own embedded
# `libqaptr_review_ffi.dylib` (amfid: "adhoc signed or signed by an unknown
# certificate chain"). Hardened runtime is only required for notarization,
# which already requires a Developer ID identity, so request it exactly when a
# real identity is used and keep local ad-hoc packages loadable.
codesign_args=(--force --sign "$identity")
if [[ "$timestamp" == "none" ]]; then
    codesign_args+=(--timestamp=none)
else
    codesign_args+=(--options runtime --timestamp)
fi

sign_macho_files() {
    local file kind
    while IFS= read -r -d '' file; do
        case "$file" in
            */Contents/MacOS/*)
                continue
                ;;
        esac
        kind=$(file -b "$file")
        case "$kind" in
            *Mach-O*)
                codesign "${codesign_args[@]}" "$file"
                ;;
        esac
    done < <(find "$app" -type f ! -path '*/_CodeSignature/*' -print0)
}

sign_bundles() {
    local bundle id
    while IFS= read -r bundle; do
        id=$(bundle_id "$bundle")
        [[ -n "$id" ]] || { echo "empty bundle identifier: $bundle" >&2; exit 1; }
        local executable
        executable=$(bundle_executable "$bundle")
        codesign "${codesign_args[@]}" --identifier "$id" "$executable"
        codesign "${codesign_args[@]}" --entitlements "$entitlements" --identifier "$id" "$bundle"
    done < <(find "$app" -type d -name '*.app' -print | awk -F/ '{ print NF "\t" $0 }' | sort -rn | cut -f2-)
}

verify_bundle() {
    local bundle id signed_id executable executable_id embedded_entitlements expected_entitlements
    expected_entitlements=$(plutil -convert xml1 -o - "$entitlements")
    while IFS= read -r -d '' bundle; do
        id=$(bundle_id "$bundle")
        signed_id=$(codesign -d --verbose=4 "$bundle" 2>&1 | sed -n 's/^Identifier=//p' | tail -n 1)
        [[ "$signed_id" == "$id" ]] || {
            echo "code-directory identifier mismatch: $bundle plist=$id signature=$signed_id" >&2
            exit 1
        }
        executable=$(bundle_executable "$bundle")
        executable_id=$(codesign -d --verbose=4 "$executable" 2>&1 | sed -n 's/^Identifier=//p' | tail -n 1)
        [[ "$executable_id" == "$id" ]] || {
            echo "executable identifier mismatch: $executable plist=$id signature=$executable_id" >&2
            exit 1
        }
        embedded_entitlements=$(codesign -d --entitlements :- "$bundle" 2>/dev/null || true)
        if [[ -z "$embedded_entitlements" ]]; then
            embedded_entitlements="$expected_entitlements"
        else
            embedded_entitlements=$(plutil -convert xml1 -o - - <<<"$embedded_entitlements")
        fi
        [[ "$embedded_entitlements" == "$expected_entitlements" ]] || {
            echo "embedded entitlements differ from packaging/signing/entitlements.plist: $bundle" >&2
            exit 1
        }
        if grep -E -q 'com\.apple\.security\.(app-sandbox|cs\.allow-jit|cs\.disable-library-validation|cs\.allow-unsigned-executable-memory|network\.client)' <<<"$embedded_entitlements"; then
            echo "broader-than-approved entitlement found: $bundle" >&2
            exit 1
        fi
        codesign --verify --strict --verbose=2 "$bundle"
    done < <(find "$app" -type d -name '*.app' -print0)
    codesign --verify --deep --strict --verbose=2 "$app"
}

audit_helper() {
    local helper helper_bin dependencies imports
    helper=$(find "$app" -type d -path '*/Contents/Library/LoginItems/QaptrHelper.app' -print -quit)
    [[ -n "$helper" ]] || { echo "nested QaptrHelper.app is missing from Contents/Library/LoginItems" >&2; exit 1; }
    [[ "$(bundle_id "$helper")" == "com.qaptr.helper" ]] || { echo "unexpected helper bundle identifier" >&2; exit 1; }
    [[ "$(plist_value LSUIElement "$helper")" == "true" ]] || { echo "helper must be an LSUIElement app" >&2; exit 1; }
    helper_bin=$(bundle_executable "$helper")

    dependencies=$(otool -L "$helper_bin")
    if grep -Fq '/Security.framework/' <<<"$dependencies"; then
        echo "release-blocking helper link audit: Security.framework is linked" >&2
        exit 1
    fi

    imports=$(nm -u "$helper_bin" 2>/dev/null || true)
    if grep -E -q '(_|^)(Sec(Item|Keychain|KeyCreateDecryptedData|KeyDecrypt|Transform)|CC(Crypt|Cryptor|KeyDerivation|Symmetric))' <<<"$imports"; then
        echo "release-blocking helper symbol audit: keychain or decryption import found" >&2
        grep -E '(_|^)(Sec(Item|Keychain|KeyCreateDecryptedData|KeyDecrypt|Transform)|CC(Crypt|Cryptor|KeyDerivation|Symmetric))' <<<"$imports" >&2 || true
        exit 1
    fi
}

# The explicit identifiers and deepest-first order prevent the U3 Tauri failure
# mode where a code directory identifier disagrees with its Info.plist.
sign_macho_files
sign_bundles
verify_bundle
audit_helper

printf 'signed and verified: %s\n' "$app"
