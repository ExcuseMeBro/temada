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
mkdir "$TMP/pcm" "$TMP/overload" "$TMP/live"
"$TMP/capture-helper" "$TMP/pcm" self-test | grep -F 'SELFTEST:PASS'
set +e
"$TMP/capture-helper" "$TMP/overload" overload-test > "$TMP/overload.log"
STATUS=$?
set -e
[ "$STATUS" = 2 ]
grep -Fx 'OVERLOAD' "$TMP/overload.log"
[ "$(find "$TMP/overload" -name '*.wav' | wc -l | tr -d ' ')" = 4 ]
"$TMP/capture-helper" "$TMP/live" live-pcm-test > "$TMP/live.log"
python3 - "$TMP/live.log" <<'PY'
import base64, pathlib, sys
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
assert lines[-1] == 'SELFTEST:PCM16-PASS'
frames = [base64.b64decode(line.removeprefix('PCM:'), validate=True) for line in lines[:-1]]
assert frames and all(0 < len(frame) <= 3200 and len(frame) % 2 == 0 for frame in frames)
# Two seconds, allowing only the resampler's initial retained filter tail.
# Native test also checks 32 seconds of sustained resampling for drift.
assert 60000 < sum(map(len, frames)) <= 64064
PY
[ -z "$(find "$TMP/live" -type f -print)" ]
printf 'Native WAV/overload + 48k stereo → streaming mono PCM16/no-disk: PASS\n'
