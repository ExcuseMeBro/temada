#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n scripts/build-native.sh scripts/test-native.sh
plutil -lint native-ui/Info.plist
TMP=$(mktemp -d -t meeting-native-test)
trap 'rm -rf "$TMP"' EXIT
swiftc -parse-as-library -O native-ui/*.swift -o "$TMP/native-test" -framework AppKit -framework SwiftUI -framework Combine
"$TMP/native-test" --self-test
printf 'Native SwiftUI/AppKit compile + synthetic state/settings/IPC checks: PASS\n'
