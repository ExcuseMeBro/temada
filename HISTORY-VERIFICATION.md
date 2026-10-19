# Temada 0.4.1 — full transcript/translation scrollback (BRAIN-1)

User requested that all transcripts and translations remain scrollable instead
of disappearing. This supersedes the compact latest-pair/line-cropping behavior,
not the compact window/font sizes or frozen Python P0–P5 acceptance criteria.

## Changes

- Display every retained row with full text in a lazy vertical stack; remove
  latest-pair suffix, line limits and misleading visible-pair controls.
- Transfer completed rows from the unchanged 48-row alignment cache into separate
  bounded history BEFORE eviction; keep the 64-row pending guard. Stable IDs and
  previous scrollback survive another Start; only explicit Clear or Quit clears
  in-memory history. Translation-first rows are visible too.
- History limits: 16MiB UTF-8 text / 10,000 retired rows; failures stop capture and
  retain accepted rows, never silently remove oldest text. These are not claims
  of infinite storage or guaranteed receipt of speech not delivered by Google.
- On macOS 15+ (including this Mac), scrolling back suspends following until the
  user returns to the bottom. macOS 14 retains text but auto-follows new input.
- Existing optional meeting files preserve full deltas and Markdown exports across
  quits. Save toggle/consent/privacy, disk/queue bounds, Stop/Quit draining, capture
  backend/model, API key handling and OS permission gates are unchanged.

## Source-current checks

- RED: `scripts/test-native.sh` failed with `HISTORY_SELFTEST: FAIL — scrollback
  lost completed transcript/translation rows beyond 48` before implementation.
- GREEN: 240 full EN/RU/UZ pairs across both sources, exact order/text/unique IDs;
  long text, restart preservation, translation-first text, invalid source, explicit
  clear, byte/row cap failures without loss and follow/backscroll state all pass.
- Updated the former file test's UI-eviction expectation to require all 120 rows
  in scrollback AND files. Independent alignment-cache limits remain tested.
- `scripts/test.sh`: 33 Rust passed, 0 failed, 1 intentionally ignored real-cloud;
  format, strict Clippy and native WAV/overload/resampling checks passed.
- `scripts/test-native.sh`: full native synthetic suite passed, including existing
  permissions, credentials, private file/archive limits, pipe drain, panel sizing,
  eight-edge/corner resize, drag routing and paste/shortcuts checks.
- `scripts/test-signing.sh`: different code hashes, identical certificate-based
  designated requirements; PASS. Final release build/self-tests, strict/deep
  signature verification and brand/bundle identity: PASS. Existing macOS 27
  microphone installTap deprecation warning remains.
- Candidate (0.4.1/build 4):
  `/Users/bro/PROJECTS/BRAINSTORM/.worktrees/meeting-ai-brain-1-macos/macos-live/dist/Temada-0.4.1-history-verified.app`.
  Same approved certificate/bundle ID, no TCC reset or trust changes.

## Not yet accepted/delivered

Candidate has NOT replaced or launched over `/Users/bro/Applications/Temada.app`.
Fresh named Quit/update/reopen approval is required. No user app/session stopped,
real audio/cloud inference/clipboard reads or user preferences changes occurred.
Real scrolling during captions, visual smoothness, device/Meet/Zoom/TCC/latency/
semantic alignment acceptance remain manual; synthetic tests do not prove these.
No Git remote exists; no shared integration/push or In Review/Done transition.
