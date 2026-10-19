# BRAIN-1 — continuous meeting lifecycle and native scroll (Temada 0.5.1)

User reported time-based stopping and scroll getting stuck. This is a local
candidate, NOT installed or real-meeting accepted. Installed Temada remains 0.4.1.
No app/session was quit, recording started, key/clipboard read or cloud API called.
Original Python STT routing and frozen P0–P5 gates are untouched.

## Changes / safety review

- Removed the app's 600-second meeting cap, as explicitly requested. The shared
  recording policy still limits cursor dictation to60s plus its15s final-turn wait.
  Fresh launch-only cloud consent remains mandatory; UI explicitly discloses
  ongoing API charges and server-requested session resumptions. No monetary cap.
- Meeting setup requests contextWindowCompression.slidingWindow and
  sessionResumption. Only a server GoAway with a valid latest resumable handle
  reconnects; no blind reconnect/retry for quota/auth/network/invalid setup errors.
  Close the previous connection before opening its replacement. Per-source limit:
  at most3 resumption attempts per60s; single12s setup, 2s buffered upload.
  Handles are bounded4096B, in memory only, never logged/archived/Debug-derived.
- Keep the SAME capture helper across resumption: no restart/repeated permission
  request. Buffer only in RAM, at most128frames/128,000PCMbytes (~4s at16kHz),
  fail visibly instead of silently discarding excess. Stop/peer-failure cancels
  pending setup. UI channel, response-size, missing-capture/server, history and
  meeting-file limits remain. Stop cleans up only owned child/socket resources.
- GoAway's same-frame final transcript is emitted BEFORE attempting resumption.
  This is still not a lossless recorder: server checkpoints may replay/omit recent
  pending output, Stop can discard unfinished speech, and resource limits/errors
  stop capture. No unlimited-uptime, latency, WER or budget guarantee.
- Replaced animated SwiftUI scrollTo/LazyVStack estimates with AppKit
  NSScrollView/NSTextView, real document geometry and incremental changed-suffix
  attributed-text updates. Preserve all model text, colors/fonts, compact sizing
  and explicit-clear behavior. No streaming-scroll animation competes with input.
  Backscroll suspends following; reaching within6pt of bottom resumes, on macOS14+.
  Re-layout on resize/font changes preserves reader offset or exact live bottom.
- CaptionPanel routes actual NSScroller hit targets to AppKit instead of dragging
  the window. Outermost3px remains resize; existing8direction/corner tests retained.
  A hidden-window route spy tests forwarding without activating user windows or
  injecting real input. Physical trackpad/thumb drag remains manual acceptance.

## Evidence

- RED duration policy: /tmp/brain-1-continuous-red.log:
  `Meeting must continue past 600s`, left `Some(600s)`, right `None`.
- Final scripts/test.sh:44 Rust PASS,0 failures,1 deliberately ignored real-cloud
  setup test; fmt, locked strict Clippy, shell/plist checks and native synthetic
  WAV/overload/PCM-no-disk gates PASS.
- Native suite and release embedded tests PASS:320 long mixed-language rows,
  partial growth, exact bottom, preserved backscroll, resume-follow, resize/font
  changes and clear; existing240-row retention, archive, permissions, credentials,
  cursor dictation, EOF/drain and panel min/max/8edge gates retained.
- Loopback WebSocket test: binary setup/update/GoAway with final text; next setup
  receives exact fixture handle, only AFTER old connection closes; original and
  resumed text retained, exactly one capture helper launched and reaped on Stop.
  Unit guards cover revoked/missing/oversized handles, reconnect-rate budget and
  audio byte/frame bounds. No real devices/accounts involved.
- Certificate stability/protected-output signing gates PASS using previously
  approved B5C97F801B29CC98705D6AC1DAAECA760B64EF62. Release build passes embedded
  native tests, strict/deep codesign and bundle identity/brand checks.
  Existing macOS27 installTap deprecation warning retained for compatibility.
- Logs: /tmp/brain-1-continuous-final-{core,native,signing,build}.log.
- Candidate: dist/Temada-0.5.1-continuous-scroll.app, dev.bro.mclbb,0.5.1/build6.
  Not launched/installed. Existing active installed app/worktree must be retained.

## External basis and remaining acceptance

https://ai.google.dev/gemini-api/docs/live-session documents approximate10minute
connection lifetime, session handles/GoAway and context compression for long Live
sessions. https://ai.google.dev/gemini-api/docs/live-api/live-translate describes
the unchanged gemini-3.5-live-translate-preview model. The translation-specific
page does NOT explicitly confirm every generic session feature. Actual account/
preview-model acceptance of these additional setup fields remains UNVERIFIED;
unsupported setup fails visibly without switching models or a paid retry loop.
No fresh cloud test was inferred from the request. Actual >10minute audio session,
provider rotations, physical scrolling on the user's meeting content, TCC/Both,
quality/latency and earlier P0–P5 acceptance remain open.

Fresh permission naming Temada Quit/update/open is required before replacing the
active installed app. Backup/verify its exact current identity and same certificate
requirement, then use the established guarded update process. No Git remote exists;
this is not integrated/pushed, In Review or Done.
