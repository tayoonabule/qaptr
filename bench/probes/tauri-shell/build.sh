#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/qaptr-u3-tauri.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cp -R "$ROOT/." "$WORK/"
cd "$WORK"
cargo tauri build --debug --bundles app
mkdir -p "$ROOT/build"
rm -rf "$ROOT/build/Qaptr Tauri Shell Probe.app"
cp -R "$WORK/src-tauri/target/debug/bundle/macos/Qaptr Tauri Shell Probe.app" "$ROOT/build/"
printf '%s\n' "$ROOT/build/Qaptr Tauri Shell Probe.app"
