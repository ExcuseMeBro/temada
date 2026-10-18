# Meeting Captions — macOS Rust streaming prototype (BRAIN-1)

Rust/egui floating window; Swift ScreenCaptureKit/AVFoundation audio capture.
**No downloaded models required.** Original transcript + EN/RU/UZ translation.
This is a buildable prototype, NOT yet a verified realtime meeting product.
Existing Python/local routed STT and frozen P0–P5 criteria are unchanged.

## Native menu-bar UI (SwiftUI + AppKit)

The new **Meeting Captions Native.app** is separate from the original app, with a
separate bundle ID/preferences domain. It does NOT replace or stop the old app.
Rust retains the same model/audio/TLS backend; the native UI starts it in a private
`--native-worker` JSON-lines mode (no egui window). No WebView or downloaded models.

```sh
bash scripts/test-native.sh
bash scripts/build-native.sh
open "dist/Meeting Captions Native.app" --args --env-file /absolute/path/to/.env
```

Build refuses an existing destination, including an app that might be running.
To build again, choose a **new** absolute `MC_NATIVE_APP=/path/NewName.app` rather
than overwriting/signing an active bundle. Only the script's private staging folder
is removed. Existing `scripts/build.sh` still builds the OLD app; do not run it
against that app while it is active.

- Menu-bar captions icon: Start/Stop, show/hide subtitles, Settings, Quit.
- Overlay has ONLY original text with translation immediately underneath each row;
  no buttons, status, speaker headings or persistent settings panels. Settings hide
  after Start; closing Settings leaves the tray app running.
- Independent font sizes and colors, background color/opacity, width/height, visible
  row count, animation switch. Drag ANYWHERE, including on caption text; resize all
  four edges/four corners (8pt edges, forgiving16pt corner targets). AppKit handles
  events before SwiftUI, so text/ScrollView cannot swallow the native window drag.
  Resize keeps the opposite edge fixed and clamps to340×140…1800×1200pt. Scroll-wheel
  text scrolling is unchanged; no global input monitors/Accessibility permission.
  Appearance,
  position, dimensions, source/target and .env **path** persist in UserDefaults.
- Consent is NOT saved; keys/captions/audio are never saved by this UI. Start is
  manual, requires consent and an explicit .env. Source/path/target changes revoke
  consent; settings cannot change the capture configuration during a session.
- Animated row insertion/autoscroll; respects macOS Reduce Motion. Old paired rows
  are bounded in memory. Unpaired backlog/oversized frames stop visibly rather than
  silently dropping text. Clear is disabled during capture to avoid resetting the
  pairing indices in the middle of an untagged provider stream.
- Original/translation deltas are split at sentence punctuation + whitespace (or
  provider `finished` boundaries), paired FIFO **within each source**, and kept
  under stable local IDs. Partial originals/translations grow in place. Interim
  originals remain provisional and are not falsely attached to untagged outputs.
  Google does not supply shared cross-stream sentence IDs: different sentence
  counts, abbreviations, reordered translation or missing boundaries can misalign
  rows. This is NOT guaranteed semantic forced alignment. Strict alignment would
  require an ID-tagged per-sentence translation stage and separate latency/cost
  validation; no silent model/provider change was made here.
- Stop/Quit closes only the owned worker's input pipe. Rust cancels its own helpers
  and sockets. If graceful Quit is not confirmed within 8s, quitting is cancelled;
  there is no force-kill of an uncertain process or any other app/session.
- Native app has a separate macOS privacy identity: grant recording permissions
  after explicit Start. Stop capture in the original app yourself first, especially
  in Both mode; the native app never closes another user's running application.

Automated native tests use synthetic text and private temporary test preferences:
SwiftUI/AppKit compilation, hidden AppKit panel sizing (empty captions must not
shrink the manually sized overlay), multilingual sentence rows, partial/out-of-order text,
source isolation, interim replacement, bounded history/backlog/UTF8, preference
round-trip/clamping, JSON wire shape, and a real short pipe-frame delivery before
EOF (writer kept open). The latter caught/fixed `FileHandle.read(upToCount:)`
waiting to fill a 16KiB read: the reader now uses `availableData` off the UI thread.
Additional hidden-panel tests check eight resize regions, bounds/fixed anchors,
native drag routing over caption content, resize events and mouse-up cancellation.
These dispatch events only to a private test panel, never another app/global mouse.
Rust tests verify consent-before-file-read,
JSON escaping and boundary ordering/backpressure. These do not prove actual native
window interactions, device capture, semantic translation alignment or smoothness.
Live native UI/Meet/Zoom/TCC checks and comparable CPU/memory/frame-time measurements
remain manual acceptance; native technology alone is not a performance guarantee.

## Default: direct Gemini Live API

Select system audio (Meet, Zoom, browser/video/player/other apps), microphone,
or **both**. Both opens two independent capture helpers and two API sessions;
source labels are retained, not diarized/mixed. Use headphones to reduce echo or
speech duplicated through the microphone. No acoustic echo cancellation yet.
System capture uses the first display and includes other apps' audio, not only
Meet/Zoom. No screen images are read/stored by this app. Microphone device selection
uses the current macOS default; device switching/revocation requires a restart.

The helper resamples to mono signed little-endian PCM16 at 16kHz, emits frames of
at most 100ms, and Rust sends them continuously over a TLS WebSocket. There are no
four-second WAV/CLI calls in this path. Native buffers can be shorter than 100ms.
Google returns original/translated text deltas which update the floating window.
Interim input events are displayed if the service sends them; actual provider
partial/segment behavior and end-to-end latency remain unverified. Rolling source
and translation text are not guaranteed sentence-aligned; each keeps a bounded
recent history. Generated audio is discarded (never played).

Model: `gemini-3.5-live-translate-preview`, official documentation lists English,
Russian and Uzbek (`en`, `ru`, `uz`). Availability can vary by account and region.
This feature-specific selection does not alter any existing CLI/global model.

**Important billing/privacy:** this is a Gemini **API key**, NOT a Gemini/ChatGPT
subscription. Free tier and access to this preview model are NOT guaranteed.
Live Translate requires AUDIO output; even though we discard audio, Google may
bill generated audio as well as audio input. Both mode can incur two sessions'
usage. The app cannot verify your billing tier, credits or dollar spend. It does
not enable billing, silently switch models/providers, or retry/reconnect. Check
Google pricing and use a billing-disabled project if you require no paid use.
The 10-minute safety stop is a duration bound, NOT a monetary budget guarantee.

Before Start, enter the key in the masked field or select an existing `.env` path
and click **Load .env**. Only `GEMINI_API_KEY` / `GOOGLE_API_KEY` are accepted;
conflicting aliases are rejected. File parsing never executes a shell, exports
variables, rewrites the file, or logs contents/errors containing secret values.
Files are bounded to 64KiB. To explicitly preload a selected file at launch:

```sh
open "dist/Meeting Captions.app" --args --env-file /absolute/path/to/.env
```

Loading a key is NOT consent to cloud processing: check the separate cost/consent
box and press Start. Changing key/path clears consent; failed loading clears the
previous key to avoid accidental use of another account. The app never writes the
key to disk, exports it to child processes, or logs it. Your existing `.env` is
still plaintext on disk; keep it private and out of Git. Close the app when done;
no claim of protection from OS swap/crash dumps or compromised device.
The key is sent only in the TLS handshake header, not URL/query or user logs.
Obtain consent from meeting participants. See Google's data retention policies,
including free-tier data handling, before sending confidential speech.

## Build / launch

macOS 14+, Apple command-line developer tools, Rust/Cargo. No CLI needed for Live.

```sh
cd macos-live
bash scripts/test.sh
bash scripts/build.sh
open "dist/Meeting Captions.app"
```

Local/ad-hoc signed; not notarized, installed, uploaded or published. Build outputs
are isolated inside this worktree. Launch, choose language/source, enter API key,
check consent, Start, then grant Screen & System Audio Recording / Microphone in
macOS Privacy settings. Real key/permission tests require the user's involvement.
The default automated suite uses fixtures only; it never accesses a real key,
device or cloud. The separately ignored `cloud_setup_only_no_audio` test requires
explicit consent and `MEETING_CAPTIONS_TEST_ENV=/absolute/path/to/.env`; it tests
TLS + authenticated setup only, sends no audio, and never starts capture.

## Streaming limits / cancellation

- At most two live sessions. 12s connection/setup timeout; 2s sends; 20s missing
  capture watchdog; 60s server-response watchdog with WebSocket heartbeats.
- 10-minute safety session cap; restart explicitly. Provider time/session limits,
  quota, permission/network errors stop visibly. No billable automatic reconnect.
- UI channel is bounded; slow consumers stop rather than silently drop captions.
  Terminal errors are separately retained even if the UI queue is full.
- Stop/close ends only this app's helpers and sockets, waits for cleanup. Neither
  another app/session nor a user's Pi/CLI process is stopped. Queued/in-flight audio
  and unfinished transcripts can be discarded; this is not a lossless recorder.
- Live audio is never written to WAV/disk by the helper; captions remain in memory.
  Quiet audio can still consume API quota. Device/meeting quality remains untested.

## Optional legacy CLI mode (experimental, NOT realtime)

Uncheck Realtime to retain the earlier four-second chunk prototype. It requires
`gemini` CLI on PATH with Google sign-in; optional `codex` with ChatGPT login does
text translation only. Launch from Terminal to inherit CLI PATH. That path uses
private temporary WAV files, bounded four-file queue, 12s backlog/40s provider
limits and discards pending/incomplete chunks on Stop. Private temporary WAVs are
cleaned after processing/session; a hard crash can leave the private directory.
No dual-source mode there. Actual subscription audio support remains unverified;
Gemini CLI was absent at implementation. AGY's inspected public CLI exposed IDE
commands, not a documented headless audio streaming API; no private auth/tokens
were extracted. This path never falls back to API billing.

The legacy runner enforces OAuth, removes API-key env variables, disables Gemini
extensions/built-in/MCP tools with deny policy/plan mode, and uses Codex read-only,
ephemeral mode with shell/MCP disabled. These are unverified integration controls,
not an audited sandbox. CLIs can retain their own session data; consult their
privacy settings. Direct Live Translate executes no tools or transcript commands.

## Evidence / open acceptance

Synthetic/no-device tests cover Rust protocol/payload/error/backpressure handling,
UTF-8 bounds, cancellation/timeouts, CLI failures; Swift compilation, synthetic
WAV round-trip/four-file overload, 48k stereo → mono16k PCM16 streaming with no audio
files; Clippy, fmt, shell/plist checks; release/ad-hoc signature checks.

With user consent, an authenticated Rust TLS/WebSocket setup-only probe passed
using the configured preview model and Uzbek target. No audio was sent. The probe
found/fixed transcript flags incorrectly nested in generationConfig (they belong
at setup level), missing Rustls crypto provider, and binary JSON server frames
previously ignored. Localhost regression now includes binary setup/text responses.

Still blocked: actual audio inference/free-tier/billing validation, measured
word-to-screen latency, EN↔UZ/RU↔UZ mixed-language quality, real Meet/Zoom/video and
microphone/both tests, TCC/revocation, network/stop behavior on live devices and long
sessions. Authenticated setup and automated mocks are not those acceptance gates.
Existing P0–P5 remain open. No Git remote exists; no dev/main/remote delivery claimed.

References:
- https://ai.google.dev/gemini-api/docs/live-api/live-translate
- https://ai.google.dev/gemini-api/docs/live-api/live-transcribe
- https://ai.google.dev/gemini-api/docs/live-guide
- https://ai.google.dev/gemini-api/docs/pricing
- https://github.com/google-gemini/jot-gemini-transcribe-macOS
