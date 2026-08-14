#!/bin/bash

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage: packaging/notarize.sh [--dry-run] APP

The real path uses an existing notarytool keychain profile. It never accepts
credentials on the command line and it does not create or store credentials.
EOF
    exit 2
}

root_dir=$(cd "$(dirname "$0")/.." && pwd)
dry_run=false
app=""

while (($# > 0)); do
    case "$1" in
        --dry-run)
            dry_run=true
            shift
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
command -v xcrun >/dev/null || { echo "xcrun is required" >&2; exit 1; }

bundle_id=$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")
team_id=$(codesign -d --verbose=4 "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p' | tail -n 1)

if [[ "$dry_run" == true ]]; then
    printf 'notarization dry-run: app=%s bundle-id=%s\n' "$app" "$bundle_id"
    printf 'notarization dry-run: requires a Developer ID signature with TeamIdentifier (current=%s)\n' "$team_id"
    printf 'notarization dry-run: xcrun notarytool submit <Qaptr.app.zip> --keychain-profile "$QAPTR_NOTARY_PROFILE" --wait\n'
    printf 'notarization dry-run: xcrun stapler staple %s\n' "$app"
    exit 0
fi

[[ -n "${QAPTR_NOTARY_PROFILE:-}" ]] || {
    echo "QAPTR_NOTARY_PROFILE is required for real notarization" >&2
    exit 1
}
[[ "$team_id" != "not set" && -n "$team_id" ]] || {
    echo "real notarization requires a Developer ID-signed app with TeamIdentifier" >&2
    exit 1
}

command -v ditto >/dev/null || { echo "ditto is required" >&2; exit 1; }
zip_path="${app%/}.notarization.zip"
rm -f "$zip_path"
ditto -c -k --keepParent "$app" "$zip_path"
xcrun notarytool submit "$zip_path" --keychain-profile "$QAPTR_NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
rm -f "$zip_path"
printf 'notarization ticket stapled and validated: %s\n' "$app"
