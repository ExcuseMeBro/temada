#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cargo fmt --check
cargo test --locked
cargo clippy --locked --all-targets -- -D warnings
bash -n scripts/build.sh scripts/test.sh
plutil -lint native/Info.plist
TMP=$(mktemp -d -t meeting-caption-test)
trap 'rm -rf "$TMP"' EXIT
swiftc -parse-as-library native/Capture.swift -o "$TMP/capture-helper" -framework ScreenCaptureKit -framework AVFoundation -framework CoreMedia
mkdir "$TMP/pcm" "$TMP/overload"
"$TMP/capture-helper" "$TMP/pcm" self-test | grep -F 'SELFTEST:PASS'
set +e
"$TMP/capture-helper" "$TMP/overload" overload-test > "$TMP/overload.log"
STATUS=$?
set -e
[ "$STATUS" = 2 ]
grep -Fx 'OVERLOAD' "$TMP/overload.log"
[ "$(find "$TMP/overload" -name '*.wav' | wc -l | tr -d ' ')" = 4 ]
printf 'Native PCM round-trip and bounded overload: PASS\n'
