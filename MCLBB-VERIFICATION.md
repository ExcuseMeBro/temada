# MCLBB local verification — 2026-10-19

BRAIN-1 refinement; native SwiftUI/AppKit UI + unchanged Rust streaming backend.
Legacy Python routed STT and frozen P0–P5 acceptance remain unchanged.

## Observed PASS

- `bash scripts/test.sh`: 31 Rust tests passed, 0 failed, 1 ignored real-cloud
  test; fmt + clippy with warnings denied; native WAV/overload/streaming PCM tests.
- `bash scripts/test-native.sh`: synthetic source-specific permission gates,
  no implicit permission prompts, at-most-once requests, stale callback rejection,
  denied/restricted microphone, unsigned rejection. Existing sentence/history,
  settings, short-pipe IPC and eight-direction panel interaction gates passed.
- Signing guards reject absent, ad-hoc and unavailable certificates before output;
  existing destination/sentinel preserved by the selected-identity signing gate.
- `bash scripts/test-signing.sh` with the selected existing Apple Development
  identity: different probe code hashes retain identical certificate-based
  designated requirements. No certificate creation/export or trust edits.
- Final native app built with the selected certificate; local icon generated from
  vector drawing. `codesign --verify --deep --strict` and bundled
  `--verify-identity` passed. TeamIdentifier: `CZVV6G7NQ4`.
- Actual two different MCLBB app builds also retained identical designated
  requirements (Apple anchor + bundle ID + certificate subject, NOT cdhash-only).
- Installed **new**, previously absent `/Users/bro/Applications/MCLBB.app` using
  exclusive atomic rename, with a private pre-change receipt. No old app replaced,
  closed or restarted; no TCC database/reset operation.
- Launched installed `dev.bro.mclbb`: PID 82078, finished launching, exact installed
  path verified using NSRunningApplication. No child capture/cloud worker at the
  observation boundary. Existing .env **path** supplied, not its contents.
- Final installed CDHash: `3a03fd000859d98304514dff8b0a150f2944b39e`.

## Still manual / not claimed

Fresh MCLBB macOS permission grant, persistence across actual user-approved restart
and later update, device audio/Meet/Zoom capture, live translation quality/latency,
visible drag/resize/smoothness and long sessions. Permission preflight and stable
signatures are not proof of a successful real TCC grant. macOS periodic confirmation
policies are not bypassed. No audio or cloud request was performed in this phase.
The real-cloud Rust test stays explicitly ignored; no fabricated live result.

Known warning: AVAudioEngine `installTap` deprecated in macOS 27 (kept for macOS 14
compatibility). Development-signed local build only; no notarization/publishing.
No remote configured; no dev/main integration, push, In Review or Done claim.
