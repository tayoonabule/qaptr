#!/bin/bash

# Deterministic contract tests for validate_release_evidence.sh.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
validator="$repo_root/bench/scripts/validate_release_evidence.sh"
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/qaptr-release-evidence-test.XXXXXX")
trap 'rm -rf "$tmp_root"' EXIT

bundle_path="$tmp_root/capture-01.bundle"
mkdir -p "$bundle_path"

write_helper() {
    local path=$1
    local permission=${2:-granted}
    cat > "$path" <<EOF
{
  "evidence_version": 1,
  "evidence_kind": "helper_capture",
  "evidence_origin": "runtime",
  "capture_source": "packaged_helper",
  "capture_state": "sealed",
  "permission_state": "$permission",
  "display_state": "present",
  "login_item_state": "started",
  "scalar_status_state": "visible",
  "capture_id": "capture-01",
  "capture_count": 1,
  "captured_at_ms": 1763164800000,
  "bundle_path": "$bundle_path"
}
EOF
}

write_review() {
    local path=$1
    local capture_id=${2:-capture-01}
    local provider_state=${3:-verified}
    cat > "$path" <<EOF
{
  "evidence_version": 1,
  "evidence_kind": "review_result",
  "evidence_origin": "runtime",
  "review_source": "packaged_review",
  "review_state": "ready",
  "analysis_state": "completed",
  "review_result_state": "present",
  "result_id": "review-01",
  "source_capture_id": "$capture_id",
  "observation_count": 1,
  "result_at_ms": 1763164805000,
  "provider_evidence_state": "$provider_state"
}
EOF
}

expect_status() {
    local expected_exit=$1
    local expected_text=$2
    shift 2
    local output
    local actual_exit
    set +e
    output=$("$validator" "$@" 2>&1)
    actual_exit=$?
    set -e
    [[ "$actual_exit" -eq "$expected_exit" ]] || {
        echo "expected exit $expected_exit, got $actual_exit: $output" >&2
        exit 1
    }
    [[ "$output" == *"$expected_text"* ]] || {
        echo "expected '$expected_text', got: $output" >&2
        exit 1
    }
}

# An idle launch has no accepted evidence shape and cannot satisfy the gate.
cat > "$tmp_root/idle.json" <<'EOF'
{
  "evidence_version": 1,
  "evidence_kind": "idle_launch",
  "evidence_origin": "runtime",
  "first_paint": true
}
EOF
expect_status 1 'helper_capture=FAIL' \
    --helper-capture "$tmp_root/idle.json" --review-result "$tmp_root/idle.json"

# Explicitly unavailable permission evidence is an external blocker, never an
# inferred pass.
write_helper "$tmp_root/helper-blocked.json" denied
write_review "$tmp_root/review.json"
expect_status 2 'helper_capture=BLOCKED' \
    --helper-capture "$tmp_root/helper-blocked.json" --review-result "$tmp_root/review.json"

# Missing provider evidence remains blocked even when capture and review fields exist.
write_helper "$tmp_root/helper.json"
write_review "$tmp_root/review-provider-blocked.json" capture-01 unverified
expect_status 2 'review_result=BLOCKED' \
    --helper-capture "$tmp_root/helper.json" --review-result "$tmp_root/review-provider-blocked.json"

# A review result for a different capture is contradictory evidence.
write_review "$tmp_root/review-mismatch.json" capture-02
expect_status 1 'review_result=FAIL' \
    --helper-capture "$tmp_root/helper.json" --review-result "$tmp_root/review-mismatch.json"

# Both explicit runtime records are required for a pass.
write_review "$tmp_root/review-valid.json"
expect_status 0 'release_evidence=PASS helper_capture=PASS review_result=PASS' \
    --helper-capture "$tmp_root/helper.json" --review-result "$tmp_root/review-valid.json"

# Missing files are blocked rather than treated as an empty or idle success.
expect_status 2 'release_evidence=BLOCKED' \
    --helper-capture "$tmp_root/missing-helper.json" --review-result "$tmp_root/review-valid.json"

printf 'validate_release_evidence tests: PASS\n'
