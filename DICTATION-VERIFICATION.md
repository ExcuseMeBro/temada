# BRAIN-1 — opt-in Uzbek → English cursor dictation (2026-10-19)

## Scope and authorization

User requested Uzbek speech translated into English at the cursor, chose Command-Space,
and approved freeing it from Spotlight. Only symbolic hotkey 64 was disabled; Spotlight
search/indexing, services, Cmd-Option-Space and other shortcuts were not disabled.
Private pre-change backup/receipt:
`/Users/bro/Library/Application Support/Temada/Backups/spotlight-shortcut-u5q5llsr/`.
Receipt state `preference-verified`; current targeted defaults export independently
confirms enabled=false and parameters [32,49,1048576]. Live keyboard routing remains
unverified. No process/session restart, injected keystrokes or TCC reset was used.
The app does not edit system shortcut preferences itself.

Same task/project, owned branch/worktree; existing Python routed STT/P0–P5 remain
unchanged. No downloaded models or changes to global provider/model selection.

## Implementation / limits

Temada 0.5.0/build5: explicit launch-only arming, API key/cloud-cost consent,
Microphone and Accessibility gates. First hotkey captures a safe target caret then
starts microphone → existing Gemini Live Translate English session. Wait for readiness;
connection setup is not instantaneous. Second press finishes one manually delimited
activity, drains bounded emitted PCM before activityEnd, waits at most 15s for final
turn and reader EOF/process success, then attempts a single AXSelectedText insertion.
No Return/Paste event, automatic clipboard access, full-field replacement or retry.
60s recording cap, 16,000 UTF-8 bytes per text stream; no meeting/dictation overlap.

Automatic activity detection is disabled only in dictation setup; meeting setup
is unchanged. Manual activity protocol reference:
https://ai.google.dev/api/live#BidiGenerateContentRealtimeInput
and https://ai.google.dev/api/live#RealtimeInputConfig .
Actual preview-model/account support has NOT been tested in this phase.

Fail closed on cancellation (including a Stop/error racing a zero exit), early or
interrupted turn, missing final turn, malformed/oversized output, changed focus/caret,
selection, password/protected fields, known terminal apps, multiline/control text,
unknown app identity or unsupported AX insertion. Draft remains launch-only for explicit
Copy. No dictation audio/text is archived; existing meeting saving/scrollback is untouched.
Focus metadata validation is not an atomic OS-wide focus lock; app-specific AX semantics
can vary. English quality and universal cursor insertion are not guaranteed.

## Final source-current evidence

- `scripts/test.sh`: 40 Rust passed, 0 failed; 1 intentionally ignored real-cloud test.
  Fmt, strict Clippy, shell/plist checks, native synthetic WAV/overload/PCM checks PASS.
- New local WebSocket tests: manual activity setup/start, pending PCM before end,
  binary final translation/turn, cancellation, interrupted/early turn rejection,
  15s missing-final timeout and owned-helper reaping. No devices or external network.
- `scripts/test-native.sh`: PASS all existing and new checks. Dictation state tests:
  explicit finish only, late final deltas, cancellation/error/empty/duplicate/bounds,
  cross-source rejection; focus/role/caret/selection/security/trust/own-app guards;
  text/known-terminal rejection; argv isolation; successful-exit/cancel races in both
  EOF orders. Existing 240-pair history, 120-entry files, IPC, permissions, credential,
  panel/preset/icon checks PASS. Tests do not acquire real Accessibility or hotkeys.
- `scripts/test-signing.sh`: PASS stable certificate requirements across different
  fixture hashes and existing destination protection. Same approved existing certificate
  B5C97F801B29CC98705D6AC1DAAECA760B64EF62; no key export/trust edit/Keychain automation.
- `scripts/build-native.sh`: release build, embedded native tests, identity/brand and
  deep/strict signature verification PASS. Candidate designated requirement matches
  installed Temada. Existing macOS27 installTap deprecation warning remains.
- Complete source diff/new files self-reviewed; `git diff --check` PASS.

Logs: `/tmp/brain-1-dictation-final-core.log`,
`/tmp/brain-1-dictation-final-native.log`, `/tmp/brain-1-dictation-final-signing.log`,
`/tmp/brain-1-dictation-final-build.log`.

## Not installed / remaining

Candidate: `/Users/bro/PROJECTS/BRAINSTORM/.worktrees/meeting-ai-brain-1-macos/macos-live/dist/Temada-0.5.0-dictation.app`.
NOT launched or installed. Installed `/Users/bro/Applications/Temada.app` remains 0.4.1;
potentially user-active and retained. Spotlight shortcut approval is NOT permission
to quit/replace Temada. Require fresh named Temada Quit/backup/update/reopen approval,
then revalidate exact current process/bundle/candidate and use private fresh receipt.
No real API key/audio/cloud call, other-app insertion or user clipboard access this phase.
Actual hotkey routing, signed-app Accessibility/TCC, account manual-activity support,
real target apps, quality/latency and broader original acceptance remain open.
No Git remote/integration/push/In Review/Done; retain task resources.
