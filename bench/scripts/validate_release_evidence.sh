#!/bin/bash

# Validate release evidence produced by a real packaged helper and review app.
# This script only validates caller-supplied evidence. It never launches an app,
# creates a capture, grants permission, or invents a review result.
set -uo pipefail

helper_evidence=""
review_evidence=""

usage() {
    cat >&2 <<'EOF'
usage: bench/scripts/validate_release_evidence.sh \
    --helper-capture PATH --review-result PATH

The inputs are plist-compatible JSON evidence records produced by an external
packaged-app run. The command prints machine-readable helper_capture= and
review_result= statuses and exits 0 for PASS, 1 for malformed/contradictory
FAIL evidence, or 2 when required external evidence is missing/blocked.
EOF
    exit 2
}

while (($# > 0)); do
    case "$1" in
        --helper-capture)
            helper_evidence=${2:?missing value for --helper-capture}
            shift 2
            ;;
        --review-result)
            review_evidence=${2:?missing value for --review-result}
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        *)
            usage
            ;;
    esac
done

[[ -n "$helper_evidence" && -n "$review_evidence" ]] || {
    echo "release_evidence=BLOCKED helper_capture=BLOCKED review_result=BLOCKED reason=missing_evidence_paths"
    exit 2
}

helper_status=PASS
review_status=PASS
helper_reason=validated
review_reason=validated

field() {
    local key=$1
    local path=$2
    plutil -extract "$key" raw -o - "$path" 2>/dev/null
}

require_file() {
    local path=$1
    [[ -f "$path" ]] || return 2
    return 0
}

require_exact() {
    local key=$1
    local expected=$2
    local path=$3
    local actual
    actual=$(field "$key" "$path") || return 1
    [[ "$actual" == "$expected" ]] || return 1
}

require_nonempty() {
    local key=$1
    local path=$2
    local actual
    actual=$(field "$key" "$path") || return 1
    [[ -n "$actual" ]] || return 1
}

require_positive_integer() {
    local key=$1
    local path=$2
    local actual
    actual=$(field "$key" "$path") || return 1
    [[ "$actual" =~ ^[1-9][0-9]*$ ]] || return 1
}

require_at_least_one() {
    local key=$1
    local path=$2
    local actual
    actual=$(field "$key" "$path") || return 1
    [[ "$actual" =~ ^[1-9][0-9]*$ ]] || return 1
}

validate_helper() {
    local path=$1
    local result
    require_file "$path"
    result=$?
    if [[ "$result" -eq 2 ]]; then
        helper_status=BLOCKED
        helper_reason=missing_evidence_file
        return
    elif [[ "$result" -ne 0 ]]; then
        helper_status=FAIL
        helper_reason=invalid_evidence_file
        return
    fi

    for requirement in \
        'evidence_version|1' \
        'evidence_kind|helper_capture' \
        'evidence_origin|runtime' \
        'capture_source|packaged_helper' \
        'capture_state|sealed' \
        'permission_state|granted' \
        'display_state|present' \
        'login_item_state|started' \
        'scalar_status_state|visible'; do
        key=${requirement%%|*}
        expected=${requirement#*|}
        if ! require_exact "$key" "$expected" "$path"; then
            actual=$(field "$key" "$path" 2>/dev/null || true)
            case "$key:$actual" in
                permission_state:denied|permission_state:blocked|permission_state:unverified|\
                display_state:missing|display_state:unavailable|display_state:blocked|display_state:unverified|\
                login_item_state:missing|login_item_state:blocked|login_item_state:unverified)
                    helper_status=BLOCKED
                    helper_reason="${key}_unavailable"
                    ;;
                *)
                    helper_status=FAIL
                    helper_reason="invalid_$key"
                    ;;
            esac
            return
        fi
    done
    if ! require_nonempty capture_id "$path" || ! [[ "$(field capture_id "$path")" =~ ^capture-[0-9]{2,}$ ]]; then
        helper_status=FAIL
        helper_reason=invalid_capture_id
        return
    fi
    if ! require_at_least_one capture_count "$path"; then
        helper_status=FAIL
        helper_reason=invalid_capture_count
        return
    fi
    if ! require_positive_integer captured_at_ms "$path"; then
        helper_status=FAIL
        helper_reason=invalid_capture_timestamp
        return
    fi
    if ! require_nonempty bundle_path "$path"; then
        helper_status=FAIL
        helper_reason=missing_bundle_path
        return
    fi
    local bundle_path
    bundle_path=$(field bundle_path "$path")
    if [[ ! -e "$bundle_path" ]]; then
        helper_status=BLOCKED
        helper_reason=sealed_bundle_not_available
        return
    fi
}

validate_review() {
    local path=$1
    local result
    require_file "$path"
    result=$?
    if [[ "$result" -eq 2 ]]; then
        review_status=BLOCKED
        review_reason=missing_evidence_file
        return
    elif [[ "$result" -ne 0 ]]; then
        review_status=FAIL
        review_reason=invalid_evidence_file
        return
    fi

    for requirement in \
        'evidence_version|1' \
        'evidence_kind|review_result' \
        'evidence_origin|runtime' \
        'review_source|packaged_review' \
        'review_state|ready' \
        'analysis_state|completed' \
        'review_result_state|present'; do
        key=${requirement%%|*}
        expected=${requirement#*|}
        if ! require_exact "$key" "$expected" "$path"; then
            review_status=FAIL
            review_reason="invalid_$key"
            return
        fi
    done
    if ! require_nonempty result_id "$path"; then
        review_status=FAIL
        review_reason=missing_result_id
        return
    fi
    if ! require_nonempty source_capture_id "$path"; then
        review_status=FAIL
        review_reason=missing_source_capture_id
        return
    fi
    if ! require_at_least_one observation_count "$path"; then
        review_status=FAIL
        review_reason=invalid_observation_count
        return
    fi
    if ! require_positive_integer result_at_ms "$path"; then
        review_status=FAIL
        review_reason=invalid_result_timestamp
        return
    fi
    # Provider evidence is an explicit signal. `not_required` is valid only for
    # a review result that makes no provider claim; `unverified` and omission
    # remain blocked rather than being treated as success.
    local provider_state
    provider_state=$(field provider_evidence_state "$path" 2>/dev/null || true)
    case "$provider_state" in
        verified|not_required) ;;
        unverified|blocked|"")
            review_status=BLOCKED
            review_reason=provider_evidence_unverified
            return
            ;;
        *)
            review_status=FAIL
            review_reason=invalid_provider_evidence_state
            return
            ;;
    esac
}

validate_helper "$helper_evidence"
validate_review "$review_evidence"

if [[ "$helper_status" == PASS && "$review_status" == PASS ]]; then
    helper_capture_id=$(field capture_id "$helper_evidence")
    review_capture_id=$(field source_capture_id "$review_evidence")
    if [[ "$helper_capture_id" != "$review_capture_id" ]]; then
        review_status=FAIL
        review_reason=capture_id_mismatch
    fi
fi

if [[ "$helper_status" == BLOCKED || "$review_status" == BLOCKED ]]; then
    overall=BLOCKED
    exit_code=2
elif [[ "$helper_status" == FAIL || "$review_status" == FAIL ]]; then
    overall=FAIL
    exit_code=1
else
    overall=PASS
    exit_code=0
fi

printf 'release_evidence=%s helper_capture=%s review_result=%s helper_reason=%s review_reason=%s\n' \
    "$overall" "$helper_status" "$review_status" "$helper_reason" "$review_reason"
exit "$exit_code"
