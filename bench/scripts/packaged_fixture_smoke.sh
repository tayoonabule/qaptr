#!/bin/bash

# Validate the packaged app with a deterministic, non-idle fixture. This keeps
# the credential-free release gate useful on machines where Screen Recording
# cannot be granted, while keeping real helper capture a separate external gate.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
output_dir="${QAPTR_PACKAGED_SMOKE_OUTPUT_DIR:-$repo_root/bench/results/packaged_fixture_smoke_$(date -u +%Y%m%dT%H%M%SZ)}"
packaged_app="${QAPTR_PACKAGED_APP:-}"
should_build=true

usage() {
    cat >&2 <<'EOF'
usage: bench/scripts/packaged_fixture_smoke.sh [--app PATH] [--output-dir PATH] [--skip-build]

Builds the normal ad-hoc package unless --app is supplied, then validates the
nested bundle and runs the packaged review executable against a deterministic
scalar capture/review fixture in an isolated HOME.
EOF
    exit 2
}

while (($# > 0)); do
    case "$1" in
        --app)
            packaged_app=${2:?missing value for --app}
            shift 2
            ;;
        --output-dir)
            output_dir=${2:?missing value for --output-dir}
            shift 2
            ;;
        --skip-build)
            should_build=false
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

mkdir -p "$output_dir"
log_file="$output_dir/packaged_fixture_smoke.log"
exec > >(tee "$log_file") 2>&1

if [[ -z "$packaged_app" && "$should_build" == true ]]; then
    package_build_dir="$output_dir/package-build"
    QAPTR_BUILD_DIR="$package_build_dir" \
        bash "$repo_root/packaging/release.sh" --dry-run --skip-reproducibility >/dev/null
    packaged_app="$package_build_dir/Qaptr.app"
fi

if [[ -z "$packaged_app" ]]; then
    echo "packaged app path is required when --skip-build is used" >&2
    exit 2
fi

packaged_app=$(cd "$packaged_app" && pwd)
review_app="$packaged_app/Contents/Applications/QaptrReview.app"
helper_app="$review_app/Contents/Library/LoginItems/QaptrHelper.app"
review_executable="$review_app/Contents/MacOS/QaptrReview"
helper_executable="$helper_app/Contents/MacOS/QaptrHelper"
review_ffi="$review_app/Contents/Frameworks/libqaptr_review_ffi.dylib"
helper_ffi="$helper_app/Contents/Frameworks/libqaptr_ffi.dylib"

for path in \
    "$packaged_app/Contents/MacOS/Qaptr" \
    "$review_app/Contents/Info.plist" \
    "$review_executable" \
    "$review_ffi" \
    "$helper_app/Contents/Info.plist" \
    "$helper_executable" \
    "$helper_ffi"; do
    [[ -e "$path" ]] || { echo "missing packaged path: $path" >&2; exit 1; }
done

[[ -x "$packaged_app/Contents/MacOS/Qaptr" ]] || exit 1
[[ -x "$review_executable" ]] || exit 1
[[ -x "$helper_executable" ]] || exit 1
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$packaged_app/Contents/Info.plist")" == "com.qaptr.app" ]]
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$review_app/Contents/Info.plist")" == "com.qaptr.review" ]]
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$helper_app/Contents/Info.plist")" == "com.qaptr.helper" ]]
[[ "$(plutil -extract LSUIElement raw -o - "$helper_app/Contents/Info.plist")" == "true" ]]
codesign --verify --deep --strict "$packaged_app" >/dev/null

# Row 197 partial closure: prove the packaged review app's helper-visibility
# path is real code, not an idle-app assumption. This compiles a tiny probe
# against the packaged `libqaptr_review_ffi.dylib` and calls the exact
# `qaptr_login_item_status` symbol the Swift review app calls from
# `ReviewBridge.loginItemEnabled()`. It proves the scalar status call is
# reachable and returns one of the documented codes (granted/denied/error)
# through the real packaged library on this machine. It does NOT prove
# SMAppService registration succeeds, since that requires a Developer-ID
# signed, Team-ID-matched build outside this ad-hoc-signed dry-run package;
# that remains an external row-197 claim tracked separately.
login_item_probe_dir="$output_dir/login-item-probe"
mkdir -p "$login_item_probe_dir"
login_item_probe_src="$login_item_probe_dir/probe.c"
login_item_probe_bin="$login_item_probe_dir/probe"
cat > "$login_item_probe_src" <<'PROBE_EOF'
#include <stdint.h>
#include <stdio.h>
extern int32_t qaptr_login_item_status(void);
int main(void) {
    int32_t code = qaptr_login_item_status();
    /* Documented contract: 1=granted, 0=denied, -2=query failure. */
    if (code != 1 && code != 0 && code != -2) {
        fprintf(stderr, "unexpected login item status code: %d\n", code);
        return 1;
    }
    printf("login_item_status_code=%d\n", code);
    return 0;
}
PROBE_EOF
clang -o "$login_item_probe_bin" "$login_item_probe_src" \
    -L "$(dirname "$review_ffi")" -lqaptr_review_ffi
login_item_status_line=$(DYLD_LIBRARY_PATH="$(dirname "$review_ffi")" "$login_item_probe_bin")
echo "$login_item_status_line"

fixture_root="$repo_root/fixtures/packaged-smoke"
progress_fixture="$fixture_root/capture-progress.json"
review_fixture="$fixture_root/review-result.json"
manifest="$repo_root/fixtures/session/manifest.csv"
ocr_root="$repo_root/crates/qaptr-privacy/fixtures/ocr"
for path in "$progress_fixture" "$review_fixture" "$manifest"; do
    [[ -f "$path" ]] || { echo "missing smoke fixture: $path" >&2; exit 1; }
done

[[ "$(plutil -lint "$progress_fixture" 2>&1)" == *"OK"* ]]
[[ "$(plutil -lint "$review_fixture" 2>&1)" == *"OK"* ]]

manifest_rows=0
while IFS=, read -r capture_id source captured_at_ms; do
    [[ "$capture_id" == "capture_id" ]] && continue
    manifest_rows=$((manifest_rows + 1))
    [[ "$capture_id" =~ ^capture-[0-9]{2}$ ]] || exit 1
    [[ "$captured_at_ms" =~ ^[0-9]+$ ]] || exit 1
    image="$ocr_root/$source.png"
    [[ -f "$image" ]] || { echo "missing fixture image: $image" >&2; exit 1; }
    file "$image" | grep -q '1600 x 1000' || { echo "unexpected fixture dimensions: $image" >&2; exit 1; }
done < "$manifest"
[[ "$manifest_rows" -eq 24 ]] || { echo "expected 24 session rows, got $manifest_rows" >&2; exit 1; }

extract() {
    plutil -extract "$1" raw -o - "$2"
}
progress_state=$(extract state "$progress_fixture")
progress_count=$(extract capture_count "$progress_fixture")
review_status=$(extract status "$review_fixture")
review_captures=$(extract capture_count "$review_fixture")
review_prepared=$(extract prepared_count "$review_fixture")
review_observations=$(extract observation_count "$review_fixture")
review_workflows=$(extract workflow_count "$review_fixture")
review_exports=$(extract export_count "$review_fixture")
provider_requests=$(extract provider_requests "$review_fixture")
[[ "$progress_state" == waiting ]] || exit 1
[[ "$progress_count" -ge 1 ]] || exit 1
[[ "$review_status" == ready ]] || exit 1
[[ "$review_captures" -ge 1 ]] || exit 1
[[ "$review_prepared" -ge 1 ]] || exit 1
[[ "$review_observations" -ge 1 ]] || exit 1
[[ "$review_workflows" -ge 1 ]] || exit 1
[[ "$review_exports" -eq 4 ]] || exit 1
[[ "$provider_requests" -eq 0 ]] || exit 1

runtime_dir="$output_dir/runtime"
mkdir -p "$runtime_dir/home"
progress_path="$runtime_dir/capture-progress.json"
control_path="$runtime_dir/capture-control.json"
permission_path="$runtime_dir/permission-status.json"
paint_path="$runtime_dir/review-first-paint.txt"
helper_pid=""
review_pid=""
terminate_app() {
    local pid=$1
    swift - "$pid" <<'SWIFT' >/dev/null 2>&1 || return 1
import AppKit

guard CommandLine.arguments.count == 2,
      let pid = Int32(CommandLine.arguments[1]),
      let application = NSRunningApplication(processIdentifier: pid)
else {
    exit(1)
}
exit(application.terminate() ? 0 : 1)
SWIFT
}
cleanup() {
    if [[ -n "$helper_pid" ]]; then
        terminate_app "$helper_pid" || kill "$helper_pid" >/dev/null 2>&1 || true
        wait "$helper_pid" >/dev/null 2>&1 || true
    fi
    if [[ -n "$review_pid" ]]; then
        terminate_app "$review_pid" || kill "$review_pid" >/dev/null 2>&1 || true
        wait "$review_pid" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT
cp "$progress_fixture" "$progress_path"
printf '{"interval_seconds":5}\n' > "$control_path"

# Permission onboarding launches the helper before final consent, but in a mode
# that may only report/request TCC state. Prove the packaged helper publishes
# its live process-scoped snapshot without starting the capture lifecycle.
rm -f "$progress_path"
HOME="$runtime_dir/home" \
QAPTR_HELPER_LOCK_PATH="$runtime_dir/helper.lock" \
QAPTR_CAPTURE_PROGRESS_PATH="$progress_path" \
QAPTR_CAPTURE_CONTROL_PATH="$control_path" \
QAPTR_PERMISSION_STATUS_PATH="$permission_path" \
"$helper_executable" \
    --permission-only true \
    --vault-root "$runtime_dir/vault" \
    >"$runtime_dir/helper-permission.log" 2>&1 &
helper_pid=$!
helper_status_ready=false
for _ in $(seq 1 30); do
    if [[ -s "$permission_path" ]]; then
        helper_status_ready=true
        break
    fi
    kill -0 "$helper_pid" >/dev/null 2>&1 || break
    sleep 0.2
done
[[ "$helper_status_ready" == true ]] || {
    echo "packaged helper did not publish permission status" >&2
    exit 1
}
[[ ! -e "$progress_path" ]] || {
    echo "permission-only helper started the capture lifecycle" >&2
    exit 1
}
[[ "$(plutil -extract version raw -o - "$permission_path")" == "2" ]]
[[ "$(plutil -extract process_id raw -o - "$permission_path")" == "$helper_pid" ]]
[[ "$(plutil -extract screen_recording_requested raw -o - "$permission_path")" == "false" ]]
[[ "$(plutil -extract accessibility_requested raw -o - "$permission_path")" == "false" ]]
[[ -n "$(plutil -extract command_token raw -o - "$permission_path")" ]]
[[ "$(plutil -extract helper_bundle_path raw -o - "$permission_path")" == "$helper_app" ]]
terminate_app "$helper_pid" || kill "$helper_pid" >/dev/null 2>&1 || true
wait "$helper_pid" >/dev/null 2>&1 || true
helper_pid=""

# Launch the packaged review executable with only scalar fixture state. HOME is
# isolated so bootstrap cannot read or mutate the developer's real history.
cp "$progress_fixture" "$progress_path"
review_log="$runtime_dir/review.log"
(
    HOME="$runtime_dir/home" \
    QAPTR_CAPTURE_PROGRESS_PATH="$progress_path" \
    QAPTR_CAPTURE_CONTROL_PATH="$control_path" \
    QAPTR_REVIEW_FFI_LIBRARY_PATH="$review_ffi" \
    QAPTR_REVIEW_PAINT_FILE="$paint_path" \
    "$review_executable" >"$review_log" 2>&1
) &
review_pid=$!

launched=false
for _ in $(seq 1 50); do
    if [[ -s "$paint_path" ]]; then
        launched=true
        break
    fi
    if ! kill -0 "$review_pid" >/dev/null 2>&1; then
        break
    fi
    sleep 0.2
done
[[ "$launched" == true ]] || {
    echo "packaged review app did not reach first paint; see $review_log" >&2
    exit 1
}

printf 'packaged_fixture_smoke PASS package=%s manifest_captures=%s scalar_capture_count=%s review_observations=%s review_workflows=%s exports=%s %s log=%s\n' \
    "$packaged_app" "$manifest_rows" "$progress_count" "$review_observations" "$review_workflows" "$review_exports" "$login_item_status_line" "$log_file"
