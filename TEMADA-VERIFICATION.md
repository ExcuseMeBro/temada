# Temada 0.4.0 / build 3 — candidate evidence

## Latest refinement: compact tray menu

User requested removal of the long provider status that widened the context menu.
Removed the disabled status menu item, its subscription and leading separator.
Full worker status/errors/cloud-cost disclosure remain in Settings; no permission
or consent gates removed. Native source absence/preserved-Settings checks,
`scripts/test-native.sh`, release build, embedded tests, strict/deep certificate
and runtime brand/identity checks PASS. Newest candidate:
`macos-live/dist/Temada-0.4.0-compact-menu.app` (NOT installed/launched).
Logs: /tmp/brain-1-temada-menu-native-tests.log,
/tmp/brain-1-temada-menu-build.log. Earlier evidence below is historical; the
compact-menu candidate supersedes the prior verified candidate for this UI change.
Installed MCLBB untouched; permission to quit/update it is still outstanding.

## Meeting files and branding evidence

2026-10-19, BRAIN-1; same task-owned BRAIN-1-macos-live worktree.
User scope: meeting files + Temada name/logo; written transcripts/translations,
not raw audio recording. Existing P0–P5 criteria remain unchanged/open.

## Source / privacy review

- Visible save toggle, folder picker, cloud-cost consent reset on save/folder
  changes. No capture on launch. Default private local App Support folder.
- JSONL journals timestamped stream frames independently of evicted UI rows.
  Status/error frames and the message field are excluded; API-key bootstrap is
  not connected to this writer. Private exclusive directory 0700, files 0600.
- Bound queued bytes to 1MiB and journal to 16MiB; asynchronous serial file writes,
  flush/close, Markdown export. Failures retain partial files and stop capture.
  Final pipe frames drain before journal completion (exit and EOF in either order).
  A failed final save cancels pending Quit; no force-kill of user apps/sessions.
- Markdown separates Original/Translation per system/microphone; provisional
  trailing input is labelled, no invented semantic alignment. Crash/power-loss
  recovery is best effort, not a lossless recording guarantee. Files plaintext;
  local/cloud backup policies and manual deletion remain the user's responsibility.
- New preferences merge defaults into old appearance settings, retaining fonts,
  frame and position. Credential storage remains launch-memory only; no .env read.
- Native visible brand/name/icon: Temada. Stable dev.bro.mclbb identity and approved
  Apple Development certificate retained. Privacy Settings may retain old name;
  actual TCC continuity after installation is still unverified.
- Generated artwork used only public brand-description prompt; no private source,
  meeting content, key or user data sent for image generation. Build rendering local.
- Root Git ignore excludes unique Meeting-* archive directories. No real meeting,
  credential, audio, generated journal or build bundle staged.

## Checks

PASS scripts/test.sh: 33 Rust tests, 0 failures, 1 intentionally ignored account
setup-only test; fmt, strict Clippy, shell/plist, synthetic WAV/overload/PCM.
No new model/audio/backend source changes; no live account inference in this phase.

PASS scripts/test-native.sh (final icon/current native source): permissions,
credentials, existing interaction/panel sizing, old preference migration,
real short-frame pipe + EOF order, both worker completion orders/exactly once.
New file tests save 120 mixed EN/RU/UZ system/mic entries beyond 48-row eviction;
verify complete first/last transcript/translation, provisional labels, JSONL time,
0700/0600, exclusive unique output, status/message exclusion, queue/file limits,
failed export does not overwrite an existing file, and save-off creates no folder.

PASS scripts/test-signing.sh using prior approved certificate SHA1
B5C97F801B29CC98705D6AC1DAAECA760B64EF62: different fixture code hashes retain
identical certificate-based requirements; existing destination protected.

Icon regression RED → GREEN: generated PNG is 1024 pixels but 245.76 AppKit points
(300dpi metadata). Initial pixel crop produced an almost-empty icon. Added center
opacity/corner transparency assertions: RED with exact error
`Invalid Temada icon: center must be opaque and corners transparent`.
Normalize artwork logical size to 1024 points; final size variants pass. Reviewed
rendered 256px icon visually: two interlocking teal/ivory dialogue bubbles on dark
rounded plate, transparent outside; no white-box background or clipped tiny corner.

PASS final release native build + all embedded synthetic tests, deep/strict
certificate signature and runtime identity/Temada name/icon-resource checks.
Final build: `macos-live/dist/Temada-0.4.0-verified.app` (NOT installed/launched).
Earlier `macos-live/dist/Temada.app` has the OLD broken icon; retained, DO NOT USE.
Native capture still emits the existing macOS27 installTap deprecation warning.
Final candidate's designated requirement matches installed MCLBB:
`identifier "dev.bro.mclbb" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: OGABEK SHOMUROTOV (HM4432ZKVW)" and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */`.

Logs: /tmp/brain-1-temada-core-tests.log,
/tmp/brain-1-temada-native-tests.log, /tmp/brain-1-temada-signing-tests.log,
/tmp/brain-1-temada-icon-red.log, /tmp/brain-1-temada-final-build.log.

## Not delivered / remaining

Installed /Users/bro/Applications/MCLBB.app untouched; no fresh named permission to
quit/replace it was given by this feature request. Require fresh confirmation to
quit ONLY MCLBB, back up old bundle and install/open renamed Temada. Do not open
another same-ID capture app concurrently or overwrite an active bundle.

No Git remote, shared queue integration/push, In Review or Done transition.
Task/worktree/resources retained. Actual app/UI/access grant continuity, meeting
file UX, real Meet/Zoom/Both audio, translation quality, measured latency/smoothness,
long sessions and original P0–P5 gates remain open; automated tests are synthetic.
