#!/bin/bash
set -euo pipefail
# Explicit opt-in gate: uses the selected existing private key locally. No audio,
# network, certificate creation, key export, trust edits, or Keychain automation.
IDENTITY=$(printf '%s' "${MC_CODESIGN_IDENTITY:-}" | tr '[:lower:]' '[:upper:]')
[[ "$IDENTITY" =~ ^[A-F0-9]{40}$ ]] || { printf 'Set approved MC_CODESIGN_IDENTITY (40 hex SHA-1).\n' >&2; exit 1; }
security find-identity -v -p codesigning | awk -v id="$IDENTITY" '$2 == id { found=1 } END { exit !found }'
TMP=$(mktemp -d -t mclbb-signing-test)
trap 'rm -rf "$TMP"' EXIT
cd "$(dirname "$0")/.."
mkdir "$TMP/existing.app"
printf 'do-not-replace' > "$TMP/existing.app/sentinel"
if MC_NATIVE_APP="$TMP/existing.app" bash scripts/build-native.sh > "$TMP/guard.log" 2>&1; then
  printf 'Build overwrote an existing destination\n' >&2; exit 1
fi
grep -F 'Refusing existing destination' "$TMP/guard.log"
[[ "$(< "$TMP/existing.app/sentinel")" == 'do-not-replace' ]]
for version in 1 2; do
  printf '#include <stdio.h>\nint main(void) { puts("MCLBB fixture %s"); return 0; }\n' "$version" | clang -x c - -o "$TMP/probe$version"
  # Bound a locked/prompting Keychain operation; stop only this owned codesign
  # process on timeout. Never auto-approve a dialog or retry an uncertain request.
  python3 - "$IDENTITY" "$TMP/probe$version" <<'PY'
import subprocess, sys
try:
    subprocess.run(['codesign', '--force', '--timestamp=none', '--identifier',
                    'dev.bro.mclbb.signing-probe', '--sign', sys.argv[1], sys.argv[2]],
                   check=True, timeout=25)
except subprocess.TimeoutExpired:
    raise SystemExit('Signing approval timed out. User must resolve Keychain; no retry performed.')
PY
  codesign --verify --strict "$TMP/probe$version"
done
INFO1=$(codesign -d -r- -vvv "$TMP/probe1" 2>&1)
INFO2=$(codesign -d -r- -vvv "$TMP/probe2" 2>&1)
printf 'Probe 1:\n%s\nProbe 2:\n%s\n' "$INFO1" "$INFO2"
R1=$(printf '%s\n' "$INFO1" | grep '^designated => ' || true)
R2=$(printf '%s\n' "$INFO2" | grep '^designated => ' || true)
H1=$(printf '%s\n' "$INFO1" | grep '^CDHash=' || true)
H2=$(printf '%s\n' "$INFO2" | grep '^CDHash=' || true)
[[ -n "$R1" && -n "$H1" && -n "$H2" && "$R1" == "$R2" && "$H1" != "$H2" && "$R1" == *'anchor apple generic'* && "$R1" != *'cdhash '* ]]
printf 'SIGNING_STABILITY: PASS — different code hashes, identical certificate-based designated requirements\n%s\n' "$R1"
printf 'This does not prove an actual macOS TCC grant or meeting capture.\n'
