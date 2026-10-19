# Configurable dictation shortcut — Temada 0.5.3 / build 8

Replaces hard-coded Command-Space with a persisted physical-key binding and dynamic
UI/status hints. Default Shift-Command-Space avoids the old Spotlight binding;
there is no claim it is globally available on every Mac.

## Behavior and safety

- Explicit Record shortcut button; Command/Control/Option plus key, optional Shift,
  or F1–F20. Bare letters, Shift-only typing and modifier-only keys are rejected.
  Escape cancels. macOS-reserved shortcuts may never reach the recorder.
- Focused button only; temporary **local** Temada event monitor intercepts menu
  equivalents. Removed after capture, cancellation, focus loss or view detachment.
  No global keyboard monitor/event tap, Input Monitoring or synthetic OS events.
- Local UserDefaults stores keycode/modifiers/label only. Malformed bindings fall
  back safely. Choosing a binding disarms it; arming/consent remain launch-only.
- Enable checks key, cloud consent, microphone, AX and signature separately; status
  names missing prerequisites. Check access does not arm. Conflicts report raw
  macOS registration code, binding and next action; partial registration cleaned up.
- Press/release gate prevents a held shortcut repeatedly toggling capture. Existing
  60s/15s limits, safe AX insertion, cancellation and explicit cloud consent remain.
- No OS shortcut changes, recording, cloud calls, real AX insertion, key reading,
  user clipboard access, active app termination or installed bundle changes here.

## Source-current evidence

- scripts/test.sh: 44 Rust PASS, 0 failed, 1 deliberately ignored real-cloud test;
  fmt, strict Clippy, WAV/overload/streaming PCM helper checks PASS.
- scripts/test-native.sh and signed release embedded suite PASS: configurable key
  mapping, modifiers/F keys, persistence/invalid data, injected conflict/cleanup,
  individual prerequisites, Check access not arming, held-key gate, focused hidden
  recorder/cancel/resign/detachment/menu-equivalent route; existing caption/history,
  files, credentials, permissions, drain, dictation safety and panel/icon gates.
- scripts/test-signing.sh PASS: different fixture hashes/same certificate DR;
  protected destination guard. Release strict/deep codesign and identity/brand PASS;
  candidate certificate DR equals installed 0.5.2. Existing macOS27 installTap warning.
- Logs: /tmp/brain-1-temada-shortcut-{core,native,signing,build}.log.

Candidate: dist/Temada-0.5.3-shortcuts.app. Not installed/launched at this boundary.
Installed /Users/bro/Applications/Temada.app remains 0.5.2; potentially user-active.
Fresh named Quit/backup/update/open approval is required before replacement.

Real global-key delivery, OS-reserved combinations, TCC/AX target insertion and
real provider/account audio behavior remain manual acceptance. These mock and
private-window tests do not prove physical hotkey success or perfect translation.
