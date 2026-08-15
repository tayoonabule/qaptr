#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
swift build -c debug
pkill -x QaptrReview 2>/dev/null || true
exec env QAPTR_DEV_MOCK_DATA=1 .build/debug/QaptrReview
