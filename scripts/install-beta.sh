#!/usr/bin/env bash
set -euo pipefail

REPO="${QAPTR_BETA_REPO:-tayoonabule/qaptr}"
TAG="${QAPTR_BETA_TAG:-}"
INSTALL_ROOT="${QAPTR_INSTALL_ROOT:-$HOME/Applications}"
KEEP_DOWNLOADS="${QAPTR_KEEP_DOWNLOADS:-0}"
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/qaptr-beta.XXXXXX")"
MOUNT_POINT=""

cleanup() {
  if [[ -n "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  fi
  if [[ "$KEEP_DOWNLOADS" != 1 ]]; then
    rm -rf "$WORK_ROOT"
  else
    printf 'Downloaded release files kept at %s\n' "$WORK_ROOT"
  fi
}
trap cleanup EXIT

fail() { printf 'Qaptr beta installer: %s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || fail "required command is missing: $1"; }
require curl
require python3
require shasum
require hdiutil
require ditto

[[ "$(uname -s)" == "Darwin" ]] || fail "this beta installer supports macOS only"
[[ "$(uname -m)" == "arm64" ]] || fail "this beta is currently Apple-silicon only"

api_url="https://api.github.com/repos/$REPO/releases"
release_json="$WORK_ROOT/releases.json"
curl --fail --silent --show-error --location --retry 3 \
  -H 'Accept: application/vnd.github+json' "$api_url" -o "$release_json"

if [[ -z "$TAG" ]]; then
  TAG="$(python3 - "$release_json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    releases = json.load(f)
for release in releases:
    if release.get("draft"):
        continue
    if release.get("prerelease"):
        print(release["tag_name"])
        break
else:
    raise SystemExit("no GitHub prerelease was found")
PY
)"
fi

release_json="$WORK_ROOT/release.json"
curl --fail --silent --show-error --location --retry 3 \
  -H 'Accept: application/vnd.github+json' \
  "https://api.github.com/repos/$REPO/releases/tags/$TAG" -o "$release_json"

asset_url="$(python3 - "$release_json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    release = json.load(f)
assets = release.get("assets", [])
for asset in assets:
    name = asset.get("name", "")
    if name.endswith(".dmg") and name.startswith("Qaptr-"):
        print(asset["browser_download_url"])
        break
else:
    raise SystemExit("release has no Qaptr DMG asset")
PY
)"

checksum_url="$(python3 - "$release_json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    release = json.load(f)
for asset in release.get("assets", []):
    if asset.get("name") in ("SHA256SUMS", "sha256sums.txt"):
        print(asset["browser_download_url"])
        break
PY
)"

dmg="$WORK_ROOT/Qaptr.dmg"
curl --fail --silent --show-error --location --retry 3 "$asset_url" -o "$dmg"
if [[ -n "$checksum_url" ]]; then
  checksums="$WORK_ROOT/SHA256SUMS"
  curl --fail --silent --show-error --location --retry 3 "$checksum_url" -o "$checksums"
  expected="$(awk -v file="$(basename "$asset_url")" '
    {
      name = $2
      sub(/^\*?[^*]*\//, "", name)
      if (name == file || name == "*" file) { print $1; exit }
    }
  ' "$checksums")"
  [[ -n "$expected" ]] || fail "checksum manifest does not contain $(basename "$asset_url")"
  actual="$(shasum -a 256 "$dmg" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || fail "DMG checksum mismatch"
else
  printf 'Warning: this release has no SHA256SUMS asset; continuing without checksum verification.\n' >&2
fi

mount_info="$(hdiutil attach "$dmg" -nobrowse -readonly -plist)"
MOUNT_POINT="$(python3 - "$mount_info" <<'PY'
import plistlib, sys
info = plistlib.loads(sys.stdin.buffer.read()) if False else plistlib.loads(sys.argv[1].encode())
for entity in info.get("system-entities", []):
    point = entity.get("mount-point")
    if point:
        print(point)
        break
PY
)"
[[ -d "$MOUNT_POINT" ]] || fail "could not mount the beta DMG"
source_app="$(find "$MOUNT_POINT" -maxdepth 2 -type d -name 'Qaptr.app' -print -quit)"
[[ -d "$source_app" ]] || fail "DMG does not contain Qaptr.app"

mkdir -p "$INSTALL_ROOT"
for proc in Qaptr QaptrReview QaptrHelper; do pkill -x "$proc" 2>/dev/null || true; done
sleep 1
staged="$INSTALL_ROOT/Qaptr.app.next"
rm -rf "$staged"
ditto "$source_app" "$staged"
rm -rf "$INSTALL_ROOT/Qaptr.app"
mv "$staged" "$INSTALL_ROOT/Qaptr.app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALL_ROOT/Qaptr.app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INSTALL_ROOT/Qaptr.app/Contents/Info.plist")"
printf 'Installed Qaptr %s (build %s) from GitHub prerelease %s at %s\n' "$version" "$build" "$TAG" "$INSTALL_ROOT/Qaptr.app"
printf 'This beta is ad-hoc signed. macOS may require Finder > Open or System Settings approval on first launch.\n'
printf 'Launch with: open %q\n' "$INSTALL_ROOT/Qaptr.app"
