#!/usr/bin/env bash
# Helper link audit (Verification Contract: "no OCR, provider, or SQLite symbols").
#
# The capture helper is the most exposed process in Qaptr: it runs continuously
# and holds only a generation public key (KTD6). This audit asserts, against the
# built binary rather than against source, that the helper cannot recognise,
# analyse, persist, or transmit anything.
#
# Complements packaging/sign.sh's audit_helper(), which covers Keychain and
# decryption symbols on the *embedded* helper at signing time. This script is
# runnable standalone and covers the wider capability surface.
#
# Usage:
#   bash bench/scripts/link_audit.sh [path/to/QaptrHelper]
# Exit status is non-zero if any forbidden capability is linked or imported.

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
default_helper="$repo_root/apps/helper/.build/arm64-apple-macosx/release/QaptrHelper.app/Contents/MacOS/QaptrHelper"
helper_bin="${1:-$default_helper}"

if [[ ! -x "$helper_bin" ]]; then
    echo "link audit: helper binary not found at $helper_bin" >&2
    echo "build it first: bash apps/helper/build_app.sh release" >&2
    exit 1
fi

echo "link audit target: $helper_bin"

dependencies=$(otool -L "$helper_bin")
imports=$(nm -u "$helper_bin" 2>/dev/null || true)
failed=0

# Each rule is (label, framework pattern, symbol pattern). An empty framework
# pattern means the capability is only detectable by imported symbol.
check() {
    local label="$1" framework_pattern="$2" symbol_pattern="$3" hits

    if [[ -n "$framework_pattern" ]]; then
        hits=$(grep -E "$framework_pattern" <<<"$dependencies" || true)
        if [[ -n "$hits" ]]; then
            echo "FAIL ${label}: framework linked" >&2
            sed 's/^/    /' <<<"$hits" >&2
            failed=1
        fi
    fi

    hits=$(grep -E "$symbol_pattern" <<<"$imports" || true)
    if [[ -n "$hits" ]]; then
        echo "FAIL ${label}: symbol imported" >&2
        sed 's/^/    /' <<<"$hits" >&2
        failed=1
    fi

    if [[ $failed -eq 0 ]]; then
        echo "ok   ${label}"
    fi
}

# Recognition belongs to the review app, never the helper: the helper seals
# pixels it cannot read back.
check "no OCR or vision" \
    '/Vision\.framework/|/VisionKit\.framework/' \
    '(_|^)(VN[A-Z]|CIDetector)'

# Durable history is owned by the review app's single writer (KTD5).
check "no SQLite" \
    '/libsqlite3' \
    '(_|^)sqlite3_'

# The helper never talks to a provider or the network.
check "no provider or network" \
    '/CFNetwork\.framework/' \
    '(_|^)(NSURLSession|NSURLConnection|CFURLRequest|CFHTTP|curl_easy)'

# Reasserted here so the standalone audit is meaningful on an unsigned build,
# not only during packaging.
check "no keychain or decryption" \
    '/Security\.framework/' \
    '(_|^)(Sec(Item|Keychain|KeyCreateDecryptedData|KeyDecrypt|Transform)|CC(Crypt|Cryptor|KeyDerivation|Symmetric))'

if [[ $failed -ne 0 ]]; then
    echo "link audit FAILED: the helper links a forbidden capability" >&2
    exit 1
fi

echo "link audit passed: no OCR, provider, SQLite, keychain, or decryption capability"
