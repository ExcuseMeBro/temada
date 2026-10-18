#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${MC_NATIVE_APP:-$PWD/dist/Meeting Captions Native.app}"
# A running user app may point here. Never overwrite/re-sign an existing bundle.
if [[ -e "$APP" ]]; then
  printf 'Refusing existing destination: %s\nChoose a NEW absolute MC_NATIVE_APP path.\n' "$APP" >&2
  exit 1
fi
[[ "$APP" = /*.app ]] || { printf 'Destination must be an absolute .app path\n' >&2; exit 1; }
mkdir -p "$PWD/dist"
STAGE=$(mktemp -d "$PWD/dist/.native-build.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$STAGE/Meeting Captions Native.app"
mkdir -p "$BUNDLE/Contents/MacOS"
cargo build --release --locked
swiftc -parse-as-library -O native/Capture.swift -o "$BUNDLE/Contents/MacOS/capture-helper" -framework ScreenCaptureKit -framework AVFoundation -framework CoreMedia
swiftc -parse-as-library -O native-ui/*.swift -o "$BUNDLE/Contents/MacOS/meeting-captions-native" -framework AppKit -framework SwiftUI -framework Combine
cp target/release/meeting-captions "$BUNDLE/Contents/MacOS/meeting-captions"
cp native-ui/Info.plist "$BUNDLE/Contents/Info.plist"
"$BUNDLE/Contents/MacOS/meeting-captions-native" --self-test
codesign --force --sign - "$BUNDLE/Contents/MacOS/capture-helper"
codesign --force --sign - "$BUNDLE/Contents/MacOS/meeting-captions"
codesign --force --sign - "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"
mkdir -p "$(dirname "$APP")"
# Atomic rename without overwriting another build/user bundle.
python3 - "$BUNDLE" "$APP" <<'PY'
import ctypes, os, sys
libc = ctypes.CDLL(None, use_errno=True)
libc.renamex_np.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
# macOS RENAME_EXCL prevents a racing writer from losing an existing bundle.
if libc.renamex_np(os.fsencode(sys.argv[1]), os.fsencode(sys.argv[2]), 4) != 0:
    raise OSError(ctypes.get_errno(), 'Exclusive app rename failed')
PY
printf '\nBuilt separate native app: %s\nNo app started; no audio/cloud used.\n' "$APP"
