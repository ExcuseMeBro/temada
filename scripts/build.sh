#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cargo build --release --locked
APP="$PWD/dist/Meeting Captions.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -parse-as-library -O native/Capture.swift -o "$APP/Contents/MacOS/capture-helper" -framework ScreenCaptureKit -framework AVFoundation -framework CoreMedia
cp target/release/meeting-captions "$APP/Contents/MacOS/meeting-captions"
cp native/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP/Contents/MacOS/capture-helper"
codesign --force --sign - "$APP"
printf '\nBuilt: %s\nLaunch from Terminal to inherit CLI PATH:\n"%s/Contents/MacOS/meeting-captions"\n' "$APP" "$APP"
