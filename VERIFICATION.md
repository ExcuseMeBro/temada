# BRAIN-1 macOS prototype verification

Observed 2026-10-18 UTC on MacBook Pro M1 Max / 64 GB / macOS 27.0.1.
Rust cargo 1.96.1; Apple Swift 6.4; eframe resolved to 0.31.1 in Cargo.lock.

On the final source candidate (including CaptureLifetime retention fix):

- `bash scripts/test.sh`: exit 0.
- `cargo fmt --check`: PASS.
- `cargo test --locked`: 10 passed, 0 failed (0.07s reported test execution).
  Tests cover multilingual JSON, code fences, invalid/schema/size/silence cases,
  missing CLI, owned-child cancellation, timeout, stdout and failure exit.
- `cargo clippy --locked --all-targets -- -D warnings`: PASS.
- `bash -n scripts/build.sh scripts/test.sh`: PASS.
- `plutil -lint native/Info.plist`: OK.
- Swift native helper compiled; synthetic 64,000-frame / 16,000-Hz WAV reopened
  with exact frame count: `SELFTEST:PASS`.
- Native overload test: fifth pending 4-second chunk exited 2, emitted `OVERLOAD`,
  and left exactly four WAVs; test-owned temporary files were deleted.
- `bash scripts/build.sh`: release Rust/Swift bundle built, exit 0.
- `codesign --verify --deep --strict 'dist/Meeting Captions.app'`: exit 0.
- Bundle size observed: 5.1 MB (not installed or notarized).
- Known compiler warning: `installTap(onBus:bufferSize:format:block:)` deprecated
  in macOS 27.0. Kept for macOS 14 compatibility; no compile failure.

Read-only account/tool checks: Codex present, `codex login status` reported
`Logged in using ChatGPT`; Gemini CLI absent. No real audio was captured or sent,
no account inference call was made, and no measured latency/quality result exists.
This evidence does NOT establish subscription audio compatibility, production
security, Meet/Zoom operation, or ultra-fast performance. See README remaining gates.

Scope review: all new code is isolated under macos-live/. No Python/STT routing,
old P1 worktree, dev/main ref, global CLI config, or meeting session was changed.
No remote is configured; no local dev integration, remote push or acceptance claim.
