# Temada — live meeting captions & translation (BRAIN-1)

Rust/egui floating window; Swift ScreenCaptureKit/AVFoundation audio capture.
**No downloaded models required.** Original transcript + EN/RU/UZ translation.
This is a buildable prototype, NOT yet a verified realtime meeting product.
Existing Python/local routed STT and frozen P0–P5 criteria are unchanged.

## Native menu-bar UI (SwiftUI + AppKit)

**Temada.app** (formerly MCLBB) preserves `dev.bro.mclbb` and the same approved
certificate/preferences domain to avoid deliberately resetting privacy grants.
It does NOT replace or stop another running app. The checked-in Temada artwork
was generated from a public brand-only prompt; build-time icon rendering is local.
Rust retains the same model/audio/TLS backend; the native UI starts it in a private
`--native-worker` JSON-lines mode (no egui window). No WebView or downloaded models.

```sh
bash scripts/test-native.sh
# Select an existing certificate with the user's approval; never export keys.
export MC_CODESIGN_IDENTITY="YOUR_APPROVED_CERTIFICATE_40_HEX_SHA1"
bash scripts/test-signing.sh  # local key use; user handles any Keychain prompt
bash scripts/build-native.sh
open "dist/Temada.app"
# In Settings, paste the Gemini API key into the masked API-key field.
```

Build refuses an existing destination, including an app that might be running.
For a candidate build, choose a **new** absolute `MC_NATIVE_APP=/path/Candidate.app`
rather than overwriting/signing an active bundle. Use the SAME approved certificate
for subsequent builds. A stable installed path such as `~/Applications/Temada.app`
should be replaced only after explicit Quit approval, ownership/idle checks and a
private pre-change receipt/backup; this script never overwrites it. Only the
script's private staging folder is removed. Signing refuses missing, ad-hoc or
unknown identities; certificate keys and trust settings are never modified.
`codesign --verify` alone proves integrity, not persistent TCC grants: the build
also rejects cdhash-only requirements and verifies the signed bundle identity. Existing `scripts/build.sh` still builds the OLD app; do not run it
against that app while it is active.

- Menu-bar captions icon: Start/Stop, show/hide subtitles, Settings, Quit.
- Overlay has ONLY original text with translation immediately underneath each row;
  no buttons, status, speaker headings or persistent settings panels. Settings hide
  after Start; closing Settings leaves the tray app running.
- Independent font sizes and colors, background color/opacity, width/height,
  animation switch; all full original/translation rows remain scrollable. Drag ANYWHERE, including on caption text; resize all
  four edges/four corners (8pt edges, forgiving16pt corner targets). AppKit handles
  events before SwiftUI, so text/ScrollView cannot swallow the native window drag.
  Resize keeps the opposite edge fixed and clamps to340×140…1800×1200pt. Scroll-wheel
  text scrolling is unchanged. Caption dragging needs no global input monitors or
  Accessibility permission; cursor dictation below does require Accessibility.
  Appearance,
  position, dimensions and source/target persist in UserDefaults.
- Enter the Gemini API key in the masked **API key** field, not a file chooser.
  The native app does NOT load .env files. The key remains in launch-only memory;
  it is not written to preferences/Keychain, logs, argv or environment variables.
  After fresh consent, a bounded JSON bootstrap frame sends it only through the
  owned worker's stdin pipe; closing that pipe still cancels the worker. Clear key
  removes the editable value; quitting requires entry again. This is not a promise
  of cryptographic zeroization or protection against OS swap/crash dumps.
- Consent is NOT saved. API keys/audio are not saved by this UI; text captions
  can now be saved locally (see Meeting files). Start is manual and requires a
  valid key and consent. Key/source/target/save-toggle/folder changes revoke
  consent; capture and recording settings cannot change during a session.
- Full scrollback, not a latest-pair suffix or 2/3-line crop. Compact layout changes
  only window/font sizes. New rows move older text upward; `LazyVStack` avoids
  eagerly creating every row view. On macOS 15+, scrolling back suspends live
  following; returning to the bottom resumes it. macOS 14 keeps full history but
  still auto-follows incoming text. Animations respect Reduce Motion.
  Starting another capture preserves earlier scrollback and unique row IDs.
  Retired history is bounded at 16MiB UTF-8 text/10,000 rows, separately from the
  48-row alignment cache (64 pending-row hard limit). Limits stop capture visibly,
  retaining accepted rows rather than silently deleting them. Oversized frames or
  missing counterpart backlogs can still stop a session. Explicit Clear text or
  quitting clears in-memory history; use meeting files for persistence across quits.
  Clear is disabled during capture to avoid resetting pairing indices.
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
- **First launch:** choose the audio source, click **Request access**, then enable
  **Temada** in Privacy Settings (an older entry may say MCLBB, not Native v2).
  Click **Check again**.
  Both may need a second explicit request for Microphone after System audio is
  granted. If macOS requires a restart, quit and reopen Temada yourself; permissions
  are never reset or bypassed. Refresh/preflight never opens an OS prompt. Requests
  are at most once per missing permission per run; denied/restricted Microphone
  directs to Settings. Unsigned test builds cannot request access/start capture.
  Start requires source-specific grants AND fresh cloud consent. No capture/network
  occurs simply by granting permission or opening the app. macOS may still impose
  its own periodic confirmation policy; this does not bypass it.
  Stop capture in the old app yourself first, especially in Both mode; Temada never
  closes another user's running application.

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

## Uzbek speech → English at the cursor (native Temada 0.5.0)

Settings → **Uzbek → English at your cursor · ⌘Space**. Enter an API key, give
fresh cloud/cost consent, grant Microphone and Accessibility explicitly, then
**Enable ⌘Space** for this launch only. Registration fails visibly if another
shortcut owns the combination; the app never edits Spotlight settings itself.
Focus an editable text caret in another app, press ⌘Space, **wait for the microphone
indicator/Listening status**, speak Uzbek, then press ⌘Space again to finish.
Connection setup can delay recording; no measured latency or perfect-English claim.

Uses the same Gemini Live Translate model, English target, microphone only; no
model download or subscription workaround. Automatic activity detection is disabled
only in this dictation session: explicit activityStart/activityEnd delimit one turn.
The second press stops/reaps the owned helper, drains its bounded remaining PCM,
sends activityEnd, and waits up to 15s for a successful final server turn and full
worker-output delivery. Recording is capped at 60s; limits/errors/cancellation,
interruption, unexpected early turns or an empty draft never trigger insertion.
Cancel dictation, Disable, tray Stop, consent/key changes and Quit cancel; a Stop
racing a successful process exit is latched and cannot become a clean insertion.
Meeting capture and dictation cannot run simultaneously. No automatic retry/fallback.

Insertion uses AXSelectedText at the captured, still-focused caret: same app,
AX element, role and selection range, editable zero-length selection only. It does
not read field contents, monitor keystrokes, replace an entire field, synthesize
Paste/Return events or automatically touch the clipboard. Known terminal apps,
password/protected fields, changed focus/caret, unknown/unsupported apps and
multiline/control-character drafts are rejected. Application AX support varies;
these metadata checks are not an atomic OS-wide focus lock. No app-specific
behavior or universal insertion support has been verified. Draft stays in memory
for **Copy English draft**, an explicit clipboard action. The first capture can
miss words spoken before connection completes; wait for readiness.

Dictation drafts are launch-only, bounded at 16,000 UTF-8 bytes per original/English
stream, and are NOT included in meeting files or caption scrollback. API audio and
generated-audio charges still apply, even though output audio is discarded. Granting
Accessibility/arming alone starts no capture or network connection. Nothing starts
until a manual hotkey press. Actual account/model manual-activity support, TCC,
⌘Space routing, microphone quality, real target-app insertion and latency remain
manual acceptance; unit/mock tests are not proof of these.

## Meeting files (native Temada)

Settings → **Meeting files** has a visible save toggle (on by default) and folder
picker. No file is created until manual Start, after source/cloud-cost consent.
Default: `~/Library/Application Support/Temada/Meetings`. Each session creates a
unique private `Meeting-<UTC timestamp>-<UUID>/` directory (0700), never overwriting
another session. `meeting.jsonl` (0600) journals timestamped original/translation
stream deltas, provisional input and finish boundaries independently of the
alignment cache and scrollback. No audio, API-key bootstrap, or status/error messages are archived.
These are **plaintext** meeting records, not encrypted; choose a private folder.
Cloud-synced destinations/OS backups may copy them. Retention/deletion is manual.

On Stop, the private serial writer flushes/closes the journal and exports
`meeting.md` (0600), with separate Original/Translation sections per audio source;
this does not invent semantic sentence alignment. Unfinished provisional input is
explicitly labelled. Menu → **Show last meeting files** opens that session folder;
the configured parent path persists, but the last-session pointer is launch-only.
Clear text clears ONLY the overlay, not saved files. Save-off creates no archive.

Disk work/export is off the UI thread; queued data is capped at 1MiB and each
journal at 16MiB. Limit/write failures stop capture visibly and retain partial files
instead of silently discarding accepted captions. Quit waits for both worker exit
AND final pipe-frame delivery, then file completion. A save failure cancels the
pending Quit and shows Settings. The existing 8s graceful-Quit deadline remains;
no force-kill is used. Abrupt crashes/power loss can lose pending/buffered writes;
JSONL is a best-effort recovery artifact, and its final line may be incomplete.
Markdown export is not guaranteed after a crash or a full disk. Provider errors,
manual Stop and the existing 10-minute cap can still truncate pending speech.
Disabling saving/clearing text does not delete earlier meetings. Generated audio
remains muted/discarded; this feature does NOT enable audio recording.

Synthetic tests cover 120 mixed-language/source entries in both scrollback and files,
240 mixed-language pairs beyond the alignment cache, stable IDs across starts,
long/translation-first text, stop-without-loss history bounds and follow/backscroll state,
private permissions, unique/exclusive output, provisional labels, status/message
exclusion, queue/file limits, export failure, save-off and appearance migration.
Real-device meeting recording/readability/performance remain manual acceptance.

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
- Live audio is never written to WAV/disk by the helper. The native Temada UI
  can save text meeting files as described above; the legacy Rust GUI does not.
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
