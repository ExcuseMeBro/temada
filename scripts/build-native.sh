#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${MC_NATIVE_APP:-$PWD/dist/Temada.app}"
# Pin a specific, user-approved certificate; never silently fall back to ad-hoc.
IDENTITY=$(printf '%s' "${MC_CODESIGN_IDENTITY:-}" | tr '[:lower:]' '[:upper:]')
[[ "$IDENTITY" =~ ^[A-F0-9]{40}$ ]] || {
  printf 'Set MC_CODESIGN_IDENTITY to the approved certificate SHA-1 (40 hex characters). Ad-hoc signing is not supported.\n' >&2
  exit 1
}
# Read public identity metadata only; never export/unlock keys or modify trust.
security find-identity -v -p codesigning | awk -v id="$IDENTITY" '$2 == id { found=1 } END { exit !found }' || {
  printf 'Approved signing identity is not available. No build/signing attempted.\n' >&2; exit 1;
}
# A running user app may point here. Never overwrite/re-sign an existing bundle.
if [[ -e "$APP" ]]; then
  printf 'Refusing existing destination: %s\nChoose a NEW absolute MC_NATIVE_APP path.\n' "$APP" >&2
  exit 1
fi
[[ "$APP" = /*.app ]] || { printf 'Destination must be an absolute .app path\n' >&2; exit 1; }
mkdir -p "$PWD/dist"
STAGE=$(mktemp -d "$PWD/dist/.native-build.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$STAGE/Temada.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cargo build --release --locked
swiftc -parse-as-library -O native/Capture.swift -o "$BUNDLE/Contents/MacOS/capture-helper" -framework ScreenCaptureKit -framework AVFoundation -framework CoreMedia
swiftc -parse-as-library -O native-ui/*.swift -o "$BUNDLE/Contents/MacOS/meeting-captions-native" -framework AppKit -framework SwiftUI -framework Combine -framework AVFoundation -framework Security
cp target/release/meeting-captions "$BUNDLE/Contents/MacOS/meeting-captions"
cp native-ui/Info.plist "$BUNDLE/Contents/Info.plist"
"$BUNDLE/Contents/MacOS/meeting-captions-native" --self-test
swift scripts/AppIcon.swift "$STAGE/Temada.iconset"
iconutil -c icns "$STAGE/Temada.iconset" -o "$BUNDLE/Contents/Resources/Temada.icns"
# Local-only development signing; no timestamp/upload/notarization or trust changes.
# Keychain prompts, if any, must be approved by the user, never automated.
codesign --force --timestamp=none --sign "$IDENTITY" "$BUNDLE/Contents/MacOS/capture-helper"
codesign --force --timestamp=none --sign "$IDENTITY" "$BUNDLE/Contents/MacOS/meeting-captions"
codesign --force --timestamp=none --sign "$IDENTITY" "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"
REQUIREMENT=$(codesign -d -r- "$BUNDLE" 2>&1 | grep '^designated => ')
[[ "$REQUIREMENT" == *'identifier "dev.bro.mclbb"'* && "$REQUIREMENT" == *'anchor apple generic'* && "$REQUIREMENT" != *'cdhash '* ]] || {
  printf 'Refusing unstable/non-Apple designated requirement.\n' >&2; exit 1;
}
"$BUNDLE/Contents/MacOS/meeting-captions-native" --verify-identity
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
printf '\nBuilt certificate-signed Temada app: %s\nNo app started; no audio/cloud used.\n' "$APP"
