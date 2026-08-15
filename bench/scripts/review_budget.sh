#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
seconds=20
output_dir="$repo_root/bench/results/review_budget_$(date -u +%Y%m%dT%H%M%SZ)"

usage() {
    cat <<'EOF'
Usage: review_budget.sh [options]

Options:
  --seconds NUMBER     Sampling window in seconds after launch. Default: 20.
  --output-dir PATH    Result directory.
  --help               Show this help.

This measures the opened QaptrReview.app's aggregate phys_footprint against
the plan's R-C7 budget (median < 150 MiB, peak < 180 MiB). It launches the
production release build, samples once per second, and reports median/peak.

Scope limitation: this smoke measurement opens the app cold with an empty or
small durable-history database. It does not yet run the plan's full 10-minute
scripted session (open, analyze a 24-capture fixture, open three
observations, generate one workflow, export all four formats), because that
fixture session and its scripted driver are U23's release-validation
responsibility, not U20's.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --seconds)
            seconds=${2:?missing value for --seconds}
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

mkdir -p "$output_dir"
samples_file="$output_dir/footprint.csv"
summary_file="$output_dir/summary.txt"
paint_file="$output_dir/paint"
printf 'epoch_seconds,phys_footprint_bytes\n' > "$samples_file"

"$repo_root/apps/review/build_app.sh" release >/dev/null
app="$repo_root/apps/review/.build/release/QaptrReview.app"
executable="$app/Contents/MacOS/QaptrReview"

QAPTR_REVIEW_PAINT_FILE="$paint_file" "$executable" >"$output_dir/stdout.log" 2>&1 &
review_pid=$!

stop_review() {
    if kill -0 "$review_pid" 2>/dev/null; then
        kill -TERM "$review_pid" 2>/dev/null || true
        wait "$review_pid" 2>/dev/null || true
    fi
}
trap stop_review EXIT INT TERM

sleep 1

for ((i = 0; i < seconds; i++)); do
    if ! kill -0 "$review_pid" 2>/dev/null; then
        printf 'review app exited before the sampling window completed\n' >&2
        exit 1
    fi
    bytes=$(footprint --noCategories -f bytes "$review_pid" 2>/dev/null | awk '/phys_footprint:/ { print $2 }') || true
    if [[ -n "$bytes" ]]; then
        printf '%s,%s\n' "$(date +%s)" "$bytes" >> "$samples_file"
    fi
    sleep 1
done

stop_review
trap - EXIT INT TERM

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

{
    printf 'samples=%s\n' "$sample_count"
    printf 'median_phys_footprint_bytes=%s\n' "$median_bytes"
    printf 'median_phys_footprint_mib=%.3f\n' "$(awk -v bytes="$median_bytes" 'BEGIN { print bytes / 1048576 }')"
    printf 'peak_phys_footprint_bytes=%s\n' "$peak_bytes"
    printf 'peak_phys_footprint_mib=%.3f\n' "$(awk -v bytes="$peak_bytes" 'BEGIN { print bytes / 1048576 }')"
    if [[ -f "$paint_file" ]]; then
        printf 'paint_epoch_ns=%s\n' "$(head -n1 "$paint_file")"
    fi
    printf 'results_dir=%s\n' "$output_dir"
} | tee "$summary_file"
