#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
command -v git >/dev/null || { echo "git is required" >&2; exit 1; }

if ! git -C "$repo_root" diff --quiet HEAD -- || ! git -C "$repo_root" diff --cached --quiet; then
    echo "reproducibility check requires a clean checkout" >&2
    exit 1
fi

work_root=$(mktemp -d "${TMPDIR:-/tmp}/qaptr-repro.XXXXXX")
trap 'rm -rf "$work_root"' EXIT

for copy in one two; do
    checkout="$work_root/$copy"
    mkdir -p "$checkout"
    git -C "$repo_root" archive HEAD | tar -x -C "$checkout"
    (
        cd "$checkout"
        env -u QAPTR_REVIEW_APP -u QAPTR_HELPER_APP -u QAPTR_BUILD_DIR \
            QAPTR_SKIP_REPRODUCIBILITY=1 bash packaging/release.sh --dry-run --skip-reproducibility
    ) >/dev/null
done

manifest() {
    local checkout=$1
    (
        cd "$checkout/packaging/.build"
        find Qaptr.app -type f -print | sort | while IFS= read -r file; do
            shasum -a 256 "$file"
        done
        dmg=$(find . -maxdepth 1 -name 'Qaptr-*.dmg' -print -quit)
        [[ -n "$dmg" ]] || { echo "DMG missing from clean package" >&2; exit 1; }
        shasum -a 256 "$dmg"
    )
}
manifest "$work_root/one" > "$work_root/one.manifest"
manifest "$work_root/two" > "$work_root/two.manifest"
if ! cmp -s "$work_root/one.manifest" "$work_root/two.manifest"; then
    echo "clean-checkout packaging is not reproducible" >&2
    diff -u "$work_root/one.manifest" "$work_root/two.manifest" >&2 || true
    exit 1
fi
printf 'clean-checkout reproducibility verified at %s\n' "$(git -C "$repo_root" rev-parse HEAD)"
