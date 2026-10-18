# Meeting Captions — experimental macOS app (BRAIN-1)

Rust/egui floating window + a small Swift ScreenCaptureKit/AVFoundation helper.
Written original transcript and translation for English, Russian and Uzbek.
This is a **buildable prototype, not a verified ultra-low-latency meeting product**.
The existing Python/local routed STT implementation and its acceptance criteria are unchanged.

## Subscription path, not Jot API billing

Jot explicitly requires a Gemini API key: https://github.com/google-gemini/jot-gemini-transcribe-macOS

This increment instead invokes the official Gemini CLI with a cached Google login.
Google documents AI Pro/Ultra accounts and cached authentication in headless mode:
https://github.com/google-gemini/gemini-cli/blob/main/docs/get-started/authentication.mdx
Audio is attached directly using `@file.wav`, not returned through a tool call:
https://github.com/google-gemini/gemini-cli/blob/main/docs/tools/file-system.md

Optional Codex translation uses the existing ChatGPT login, **for text only**.
Codex is NOT an audio transcription backend:
https://github.com/openai/codex

The app does not implement browser automation, reuse cookies, extract tokens,
change global CLI settings, or silently fall back to paid APIs. Google OAuth is
selected/enforced in the temporary workspace; API-key environment variables are
removed from child commands. Codex is pinned to ChatGPT login. The CLI's existing
model selection remains unchanged. Older CLI versions may reject the protective
flags/settings; that is a visible error, not permission to bypass them.

**Unverified:** actual Gemini subscription audio capability, account quotas and
end-to-end latency on this machine. Gemini CLI was absent at implementation time.
Codex `login status` reported `Logged in using ChatGPT`. That is auth metadata,
not proof of successful translation. No account requests or real meeting audio
were sent during implementation. Subscription authentication does not guarantee
all audio/model features are available. If Google rejects audio, this backend is
blocked; an explicitly approved API or the existing local STT backend is needed.

## Build and launch

Requires macOS 14+, Apple command-line developer tools, Rust/Cargo, and the official
CLIs available on PATH. Install/sign in yourself in Terminal (the app never enters
credentials or accepts consent on your behalf):

```sh
# If absent; installs official CLI globally, a user-controlled setup step:
npm install -g @google/gemini-cli
gemini                     # choose Sign in with Google; finish browser consent
codex login                # only if using ChatGPT translation
```

From `macos-live/`:

```sh
bash scripts/test.sh
bash scripts/build.sh
"$PWD/dist/Meeting Captions.app/Contents/MacOS/meeting-captions"
```

Launch from the signed bundle, **from Terminal**, so it inherits your CLI PATH.
Build is local/ad-hoc signed, not notarized, installed, published or uploaded.
Select target language and either `system` (Meet/Zoom/browser playback) or
`microphone`. Select optional Codex translation, explicitly consent to cloud
processing, then Start. Grant the macOS audio/microphone permission when prompted.
System capture uses the first display's audio filter and saves no video frames.
This prototype does not detect Meet/Zoom processes or capture only one app: system
mode can include OTHER apps' audio. Obtain meeting participants' consent.

## Latency, buffering and stop behavior

- Four-second audio chunks: latency is **at least chunk collection + CLI startup +
  network/inference**, plus another CLI call if Codex translation is enabled.
- Gemini transcribes and translates in a single request; Codex mode replaces its
  translation with a second text request. No unmeasured speed claim.
- One provider request in flight. Four WAV files maximum; capture exits visibly
  on overload. Queued chunks older than 12 seconds stop the session rather than
  silently presenting increasingly stale captions. Provider deadline: 40 seconds.
- Stop/close cancels this app's helper and owned provider process group, waits for
  worker cleanup, deletes temporary audio. It never stops another Pi/CLI/app.
- **Stop discards unfinished (<4s), in-flight and queued chunks.** Not a lossless
  recorder or meeting archive. The UI keeps only the latest 100 caption pairs.
- No hot word-boundary overlap/VAD, no partial live tokens, no dual-source mixing,
  no diarization/export/reconnect yet. Permission revocation/provider errors are
  visible, not retried silently. Quiet/silent audio still consumes provider quota.

## Privacy and security boundary

Start requires explicit consent. Audio goes to Google; optional original transcript
goes to OpenAI. Raw WAVs live inside a private OS temporary directory and are removed
after processing/session cleanup. A hard crash may leave the private temp directory
behind; no crash-recovery deletion of unknown directories is performed. Caption
text is only held by this app in memory, not logged. Provider stderr is not echoed
because it can contain sensitive data; errors show provider/exit status and next
steps. CLI output is bounded, held in anonymous temporary files and discarded.

Gemini uses no extensions, an empty built-in/MCP allowlist, a deny-tools policy and
plan mode. The temporary directory alone is trusted via `--skip-trust`, not a user's
repository. Codex uses read-only sandboxing, ephemeral execution, shell-tool disable
and an empty MCP configuration override. Audio/transcripts are marked untrusted data.
These controls need integration verification against the installed CLI versions;
this is **not a claim of an independently audited agent sandbox**. Managed admin
policies/user CLI plugins may affect behavior. CLIs still use their own account
configuration and may cache session/audio/transcript data outside our directory;
review their retention and privacy policies. No promise of fully local processing.

## Evidence / remaining acceptance

Automated checks use synthetic PCM only (no devices, cloud calls or permissions):
Rust parser/multilingual/size/failure/cancellation/timeout tests; Clippy; formatting;
Swift compile; 4-second WAV round-trip; four-file overload; plist/shell validation;
release bundle build/ad-hoc signature checks.

Still required before product acceptance: real signed-in Gemini audio probe,
EN↔UZ/RU↔UZ quality on consented mixed-language audio, timing from spoken word to
rendered caption, actual Meet and Zoom playback, microphone and screen-audio TCC
behavior, permission revocation, Stop during capture/request, long session and
quota/backlog handling. Subscription CLI mode may fail the ultra-fast requirement;
a persistent realtime API connection or warm local backend is then necessary.

Existing project P0–P5 acceptance (including real-audio benchmarks) remains open.
No remote is configured; no dev/main integration or remote delivery is claimed.
