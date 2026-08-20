#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
review="$repo_root/apps/review/Sources/QaptrReview/QaptrReviewApp.swift"
helper="$repo_root/apps/helper/Sources/QaptrHelper/main.swift"

fail() {
    printf 'macOS command validation failed: %s\n' "$1" >&2
    exit 1
}

[[ -f "$review" ]] || fail "missing review app source"
[[ -f "$helper" ]] || fail "missing helper source"
if grep -Eq 'menu\.addItem\(withTitle:.*action:[[:space:]]*nil' "$helper"; then
    fail "helper menu contains a visible title-only item"
fi

if grep -Eq 'Settings[[:space:]]*\{[[:space:]]*EmptyView\(\)' "$review"; then
    fail "review Settings scene still uses EmptyView"
fi
grep -Eq 'model:[[:space:]]*appDelegate\.model' "$review" \
    || fail "review Settings scene is not wired to the shared model"
grep -q 'navigation.surface = .settings' "$review" \
    || fail "review Settings command does not select the Settings surface"
grep -q 'func showObservations()' "$review" \
    || fail "review observations command has no deterministic handler"
grep -q 'navigation.surface = .review' "$review" \
    || fail "review observations command does not select the Review surface"
grep -q 'keyboardShortcut' "$review" \
    || fail "review commands have no keyboard shortcuts"
grep -q 'Button("Show Capture Observations"' "$review" \
    || fail "review show command is missing"
grep -q 'Button("Settings…"' "$review" \
    || fail "review settings command is missing"
grep -q 'action: #selector(showQaptr(_:))' "$helper" \
    || fail "helper show menu item has no selector"
grep -q 'action: #selector(openReviewSettings(_:))' "$helper" \
    || fail "helper settings menu item has no selector"
grep -q 'action: #selector(quit(_:))' "$helper" \
    || fail "helper quit menu item has no selector"
grep -q '@objc private func showQaptr' "$helper" \
    || fail "helper show selector has no handler"
grep -q '@objc private func openReviewSettings' "$helper" \
    || fail "helper settings selector has no handler"
grep -q '@objc private func quit' "$helper" \
    || fail "helper quit selector has no handler"
grep -q 'keyEquivalentModifierMask = \[.command\]' "$helper" \
    || fail "helper menu shortcuts are not explicitly command-scoped"

printf 'macOS command validation passed\n'
