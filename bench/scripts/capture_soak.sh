#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
hours=12
capture_interval_seconds=600
max_dimension=1920
output_dir="$repo_root/bench/results/capture_soak_$(date -u +%Y%m%dT%H%M%SZ)"

usage() {
    cat <<'EOF'
Usage: capture_soak.sh [options]

Options:
  --hours NUMBER                       Run duration in hours. Decimals are accepted.
  --capture-interval-seconds NUMBER    Delay between capture rounds. Default: 600.
  --max-dimension PIXELS               Longest output edge. Default: 1920.
  --output-dir PATH                    Result directory.
  --help                               Show this help.

Example smoke test:
  bash bench/scripts/capture_soak.sh --hours 0.01 --capture-interval-seconds 5
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hours)
            hours=${2:?missing value for --hours}
            shift 2
            ;;
        --capture-interval-seconds)
            capture_interval_seconds=${2:?missing value for --capture-interval-seconds}
            shift 2
            ;;
        --max-dimension)
            max_dimension=${2:?missing value for --max-dimension}
            shift 2
            ;;
        --output-dir)
            output_dir=${2:?missing value for --output-dir}
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            printf 'unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

duration_seconds=$(awk -v hours="$hours" 'BEGIN {
    if (hours <= 0) exit 1
    seconds = int(hours * 3600 + 0.5)
    if (seconds < 1) seconds = 1
    print seconds
}') || {
    printf '%s\n' '--hours must be a positive number' >&2
    exit 2
}

for value_name in capture_interval_seconds max_dimension; do
    value=${!value_name}
    if ! awk -v value="$value" 'BEGIN { exit !(value > 0) }'; then
        printf '%s must be a positive number\n' "$value_name" >&2
        exit 2
    fi
done

mkdir -p "$output_dir"
samples_file="$output_dir/footprint.csv"
helper_log="$output_dir/helper.log"
summary_file="$output_dir/summary.txt"
printf 'epoch_seconds,total_phys_footprint_bytes,process_count\n' > "$samples_file"

"$repo_root/apps/helper/build_app.sh" release >/dev/null
helper_executable="$repo_root/apps/helper/.build/release/QaptrHelper.app/Contents/MacOS/QaptrHelper"

QAPTR_HELPER_LOCK_PATH="$output_dir/helper.lock" \
QAPTR_CAPTURE_PROGRESS_PATH="$output_dir/capture-progress.json" \
QAPTR_CAPTURE_CONTROL_PATH="$output_dir/capture-control.json" \
QAPTR_PERMISSION_STATUS_PATH="$output_dir/permission-status.json" \
"$helper_executable" \
    --interval-seconds "$capture_interval_seconds" \
    --max-dimension "$max_dimension" \
    --vault-root "$output_dir/vault" \
    > "$helper_log" 2>&1 &
helper_pid=$!

stop_helper() {
    if kill -0 "$helper_pid" 2>/dev/null; then
        kill -TERM "$helper_pid" 2>/dev/null || true
        wait "$helper_pid" 2>/dev/null || true
    fi
}
trap stop_helper EXIT INT TERM

process_tree() {
    local root_pid=$1
    local pending="$root_pid"
    local current child
    local all=""

    while [[ -n "$pending" ]]; do
        current=${pending%% *}
        if [[ "$pending" == *" "* ]]; then
            pending=${pending#* }
        else
            pending=""
        fi
        all="$all $current"
        for child in $(pgrep -P "$current" 2>/dev/null || true); do
            pending="$pending $child"
        done
        pending=${pending# }
    done

    printf '%s\n' "${all# }"
}

sample_footprint() {
    local pids_text footprint_output total_bytes process_count
    local -a pids

    pids_text=$(process_tree "$helper_pid")
    read -r -a pids <<< "$pids_text"
    process_count=${#pids[@]}
    footprint_output=$(footprint --noCategories -f bytes "${pids[@]}" 2>/dev/null) || return 1
    total_bytes=$(awk '$1 == "phys_footprint:" { total += $2 } END { print total + 0 }' <<< "$footprint_output")
    [[ "$total_bytes" -gt 0 ]] || return 1
    printf '%s,%s,%s\n' "$(date +%s)" "$total_bytes" "$process_count" >> "$samples_file"
}

started_epoch=$(date +%s)
deadline=$((started_epoch + duration_seconds))
while [[ $(date +%s) -lt $deadline ]]; do
    if ! kill -0 "$helper_pid" 2>/dev/null; then
        printf 'helper exited before soak completed\n' >&2
        wait "$helper_pid"
        exit 1
    fi
    sample_footprint || printf 'warning: footprint sample failed at %s\n' "$(date -u +%FT%TZ)" >&2
    sleep 1
done

stop_helper
trap - EXIT INT TERM

metric_values() {
    local event=$1
    local key=$2
    local mode=${3:-}
    awk -v event="$event" -v key="$key" '
        $1 == "event=" event {
            matches_mode = 1
            if (mode != "") {
                matches_mode = 0
                for (field = 1; field <= NF; field++) {
                    if ($field == "mode=" mode) matches_mode = 1
                }
            }
            if (!matches_mode) next
            for (field = 1; field <= NF; field++) {
                split($field, pair, "=")
                if (pair[1] == key) print pair[2]
            }
        }
    ' mode="$mode" "$helper_log"
}

median() {
    sort -n | awk '
        { values[NR] = $1 }
        END {
            if (NR == 0) exit 1
            if (NR % 2) print values[(NR + 1) / 2]
            else printf "%.3f\n", (values[NR / 2] + values[NR / 2 + 1]) / 2
        }
    '
}

peak() {
    sort -n | tail -1
}

memory_values=$(awk -F, 'NR > 1 { print $2 }' "$samples_file")
sample_count=$(awk 'END { print NR - 1 }' "$samples_file")
median_bytes=$(median <<< "$memory_values")
peak_bytes=$(peak <<< "$memory_values")
capture_values=$(metric_values capture latency_ms || true)
single_capture_values=$(metric_values capture latency_ms single || true)
multiple_capture_values=$(metric_values capture latency_ms multiple || true)
tick_values=$(metric_values tick latency_ms || true)
single_set_values=$(metric_values tick single_latency_ms || true)
multiple_set_values=$(metric_values tick multiple_latency_ms || true)
capture_count=$(grep -c '^event=capture ' "$helper_log" || true)
tick_count=$(grep -c '^event=tick ' "$helper_log" || true)
skip_count=$(grep -c '^event=skip ' "$helper_log" || true)

{
    printf 'duration_seconds=%s\n' "$duration_seconds"
    printf 'samples=%s\n' "$sample_count"
    printf 'median_phys_footprint_bytes=%s\n' "$median_bytes"
    printf 'median_phys_footprint_mib=%.3f\n' "$(awk -v bytes="$median_bytes" 'BEGIN { print bytes / 1048576 }')"
    printf 'peak_phys_footprint_bytes=%s\n' "$peak_bytes"
    printf 'peak_phys_footprint_mib=%.3f\n' "$(awk -v bytes="$peak_bytes" 'BEGIN { print bytes / 1048576 }')"
    printf 'captures=%s\n' "$capture_count"
    if [[ -n "$capture_values" ]]; then
        printf 'median_capture_latency_ms=%s\n' "$(median <<< "$capture_values")"
        printf 'peak_capture_latency_ms=%s\n' "$(peak <<< "$capture_values")"
    fi
    if [[ -n "$single_capture_values" ]]; then
        printf 'median_single_capture_latency_ms=%s\n' "$(median <<< "$single_capture_values")"
        printf 'peak_single_capture_latency_ms=%s\n' "$(peak <<< "$single_capture_values")"
    fi
    if [[ -n "$multiple_capture_values" ]]; then
        printf 'median_multiple_capture_latency_ms=%s\n' "$(median <<< "$multiple_capture_values")"
        printf 'peak_multiple_capture_latency_ms=%s\n' "$(peak <<< "$multiple_capture_values")"
    fi
    if [[ -n "$single_set_values" ]]; then
        printf 'median_single_set_latency_ms=%s\n' "$(median <<< "$single_set_values")"
        printf 'peak_single_set_latency_ms=%s\n' "$(peak <<< "$single_set_values")"
    fi
    if [[ -n "$multiple_set_values" ]]; then
        printf 'median_multiple_set_latency_ms=%s\n' "$(median <<< "$multiple_set_values")"
        printf 'peak_multiple_set_latency_ms=%s\n' "$(peak <<< "$multiple_set_values")"
    fi
    printf 'ticks=%s\n' "$tick_count"
    printf 'skips=%s\n' "$skip_count"
    if [[ -n "$tick_values" ]]; then
        printf 'median_tick_latency_ms=%s\n' "$(median <<< "$tick_values")"
        printf 'peak_tick_latency_ms=%s\n' "$(peak <<< "$tick_values")"
    fi
    printf 'results_dir=%s\n' "$output_dir"
} | tee "$summary_file"
