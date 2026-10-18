# Meeting Captions — macOS Rust streaming prototype (BRAIN-1)

Rust/egui floating window; Swift ScreenCaptureKit/AVFoundation audio capture.
**No downloaded models required.** Original transcript + EN/RU/UZ translation.
This is a buildable prototype, NOT yet a verified realtime meeting product.
Existing Python/local routed STT and frozen P0–P5 criteria are unchanged.

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

Before Start, enter the key in the masked field and explicitly consent to cloud
processing/possible charges. The app holds the key only in process memory (not
persisted to disk, exported to child processes, or logged). Clear/close the app
when done; no claim of protection from OS swap/crash dumps or compromised device.
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
No key/device/cloud requests are made by automated tests.

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

Still blocked: authenticated real Live handshake/model/free-tier access, actual
word-to-screen latency, EN↔UZ/RU↔UZ mixed-language quality, real Meet/Zoom/video and
microphone/both tests, TCC/revocation, network/stop behavior on live devices, long
sessions, quota/billing validation. Automated mocks are not those acceptance gates.
Existing P0–P5 remain open. No Git remote exists; no dev/main/remote delivery claimed.

References:
- https://ai.google.dev/gemini-api/docs/live-api/live-translate
- https://ai.google.dev/gemini-api/docs/live-api/live-transcribe
- https://ai.google.dev/gemini-api/docs/live-guide
- https://ai.google.dev/gemini-api/docs/pricing
- https://github.com/google-gemini/jot-gemini-transcribe-macOS
