#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD="$ROOT/build"
APP="$BUILD/QaptrSwiftUIShell.app"
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc "$ROOT/main.swift" -o "$APP/Contents/MacOS/QaptrSwiftUIShell" -parse-as-library -target arm64-apple-macos15.0 -framework AppKit -framework CoreGraphics -framework SwiftUI
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
codesign --force --deep --sign - --identifier com.qaptr.u3.swiftui "$APP"
printf '%s\n' "$APP"
