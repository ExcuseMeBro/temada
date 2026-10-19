# Temada brand tray — 0.5.4 / build 9

User approved retaining Temada's own logo shape while making it monochrome.
StatusIcon now draws a resolution-independent, flat silhouette traced from the
existing assets/Temada.png: interlocking bubbles, two tails, central negative gap.
No system chat/caption symbol, rounded app tile, gradient, badge or asset mutation.
Both states retain the brand shape; recording status stays in the existing tooltip.
18pt NSImage.isTemplate lets AppKit supply light/dark/highlight tint.

Evidence:
- RED: previous generic SF caption-bubble fixture fails exactly
  `STATUS_ICON_SELFTEST: FAIL — Temada's two speech-bubble tails are missing (generic chat icon)`.
- GREEN: full scripts/test-native.sh and signed-release embedded suite PASS, including
  independent tail/lobe/gap pixel landmarks in both appearances, template flag,
  18pt size, monochrome RGB, transparent background and untouched full-color logo.
  All existing shortcut/AX safety, permission, credential, files/drain, scroll/history,
  panel and signing-guard tests preserved.
- Visual comparison of existing brand artwork with144px black-on-white vector preview:
  /tmp/temada-brand-tray-on-white.png. Transparent preview also retained separately.
- Release strict/deep codesign and runtime identity/brand PASS. Backend/audio/dependencies
  and signer/build scripts unchanged; previous44RustPASS/1ignored and signer-stability
  evidence from0.5.3 remain valid. Known macOS27 installTap warning unchanged.
- Logs /tmp/brain-1-temada-brand-tray-{red,native,build}.log.

Candidate dist/Temada-0.5.4-brand-tray.app is NOT installed/launched. Installed
/Users/bro/Applications/Temada.app remains0.5.3, potentially user-active. No Quit,
recording/cloud/API/clipboard/OS shortcut changes in this phase. Fresh named
Temada Quit/backup/install/reopen permission required; actual menu-bar appearance
remains user acceptance, not inferred from raster tests.
