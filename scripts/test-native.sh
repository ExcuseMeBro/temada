#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n scripts/build-native.sh scripts/test-native.sh scripts/test-signing.sh
plutil -lint native-ui/Info.plist
TMP=$(mktemp -d -t meeting-native-test)
trap 'rm -rf "$TMP"' EXIT
swiftc -parse-as-library -O native-ui/*.swift -o "$TMP/native-test" -framework AppKit -framework SwiftUI -framework Combine -framework AVFoundation -framework Security
"$TMP/native-test" --self-test
# Fail closed BEFORE creating output or invoking any signing operation.
for identity in '' '-' '0000000000000000000000000000000000000000'; do
  if MC_CODESIGN_IDENTITY="$identity" MC_NATIVE_APP="$TMP/guard.app" bash scripts/build-native.sh > "$TMP/guard.log" 2>&1; then
    printf 'Signing guard incorrectly accepted absent/ad-hoc/unknown identity\n' >&2; exit 1
  fi
  [[ ! -e "$TMP/guard.app" ]]
done
if "$TMP/native-test" --verify-identity > "$TMP/unsigned.log" 2>&1; then
  printf 'Unsigned executable passed bundle identity check\n' >&2; exit 1
fi
swift scripts/AppIcon.swift "$TMP/MCLBB.iconset"
iconutil -c icns "$TMP/MCLBB.iconset" -o "$TMP/MCLBB.icns"
[[ -s "$TMP/MCLBB.icns" ]]
printf 'Signing guards + unsigned bundle rejection + brand icon: PASS\n'
printf 'Native SwiftUI/AppKit compile + synthetic state/settings/IPC checks: PASS\n'
