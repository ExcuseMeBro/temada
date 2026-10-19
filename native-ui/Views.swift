import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0xF2F4F8
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
    var hex: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
}
struct CaptionOverlay: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var captions: Captions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var follow = CaptionFollowState()
    var body: some View {
        let a = preferences.appearance
        let rows = captions.rows
        let animation: Animation? = a.animations && !reduceMotion ? .easeOut(duration: 0.18) : nil
        // Deliberately NO controls, status, source headers or placeholders here.
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(rows) { pair in
                        VStack(alignment: .leading, spacing: 3) {
                            // Compact window/fonts, but never truncate transcript history.
                            Text(pair.original).font(.system(size: a.originalSize, weight: .regular)).foregroundStyle(Color(hex: a.originalColor))
                                .fixedSize(horizontal: false, vertical: true)
                            if !pair.translation.isEmpty {
                                Text(pair.translation).font(.system(size: a.translationSize, weight: .medium)).foregroundStyle(Color(hex: a.translationColor))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(pair.id)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(12)
                .animation(animation, value: rows.map(\.id))
            }
            .captionScrollFollowing($follow)
            .onChange(of: captions.rows) { _, rows in
                if rows.isEmpty { follow.latest = true }
                if follow.latest, let last = rows.last { withAnimation(animation) { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: a.backgroundColor).opacity(a.opacity), in: RoundedRectangle(cornerRadius: 16))
    }
}
@MainActor func captionHostingView(preferences: Preferences, captions: Captions) -> NSHostingView<CaptionOverlay> {
    let hosting = NSHostingView(rootView: CaptionOverlay(preferences: preferences, captions: captions))
    // Empty captions must not let SwiftUI's 40pt intrinsic width resize the panel.
    hosting.sizingOptions = []
    return hosting
}
struct NativeSettings: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var worker: StreamingWorker
    @ObservedObject var permissions: RecordingPermissions
    @ObservedObject var credentials: APICredentials
    @ObservedObject var meetingFiles: MeetingFiles
    @ObservedObject var dictation: EnglishDictation
    @State private var consent = false
    @State private var pasteFailed = false
    var toggleOverlay: () -> Void
    var clear: () -> Void
    var start: (Bool) -> Void
    private func color(_ path: WritableKeyPath<Appearance, String>) -> Binding<Color> {
        Binding(get: { Color(hex: preferences.appearance[keyPath: path]) }, set: { preferences.appearance[keyPath: path] = $0.hex })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    Image(nsImage: NSImage(named: NSImage.Name("Temada")) ?? NSImage(systemSymbolName: "captions.bubble.fill", accessibilityDescription: "Temada")!)
                        .resizable().scaledToFit().frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Temada").font(.system(size: 32, weight: .bold, design: .rounded))
                        Text("Meetings, without language barriers").font(.subheadline).foregroundStyle(.secondary)
                        Text("Understand every meeting.   EN / RU / UZ").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                GroupBox("1 · macOS access") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 20) {
                            Label(permissions.screenGranted ? "System audio · Ready" : "System audio · Needs access", systemImage: permissions.screenGranted ? "checkmark.shield.fill" : "lock.shield")
                            Label(permissions.microphoneGranted ? "Microphone · Ready" : "Microphone · Needs access", systemImage: permissions.microphoneGranted ? "checkmark.circle.fill" : "mic.slash")
                        }.font(.callout)
                        HStack {
                            Button(permissions.requesting ? "Waiting for macOS…" : "Request access") { permissions.request(source: preferences.appearance.source) }
                                .disabled(permissions.requesting || !permissions.certificateSigned)
                            Button("Privacy Settings") { permissions.openSettings(source: preferences.appearance.source) }
                            Button("Check again") { permissions.refresh() }
                        }
                        Text(permissions.canStart(source: preferences.appearance.source) ? "Required macOS access is ready. No recording until cloud consent and Start." : (permissions.message.isEmpty ? "Only the selected audio source needs access. Requesting permission does not record or send audio." : permissions.message))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }.disabled(worker.running)
                GroupBox("2 · Audio & Gemini Live") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            SecureField("Gemini API key", text: $credentials.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Gemini API key")
                            Button("Paste") { pasteFailed = !credentials.pasteKey(from: .general) }
                                .help("Paste the copied Google Gemini API key (⌘V also works in the field)")
                            Button("Clear key") { credentials.apiKey = "" }.disabled(credentials.apiKey.isEmpty)
                        }
                        if pasteFailed {
                            Text("Copy a valid API key as plain text, then paste again. Existing key was not changed.").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("API key stays in memory for this launch only. It is not saved; enter it again after quitting Temada.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Picker("Audio", selection: $preferences.appearance.source) {
                                Text("All system audio / video").tag("system"); Text("Microphone").tag("microphone"); Text("Both (two sessions)").tag("both")
                            }
                            Picker("Translate to", selection: $preferences.appearance.target) {
                                Text("O‘zbekcha").tag("uz"); Text("English").tag("en"); Text("Русский").tag("ru")
                            }
                        }
                        Text("Audio goes to Google. API billing is separate from subscriptions; generated audio is muted but may still be billed. Both uses two sessions. No automatic reconnect; 10-minute safety stop.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Use headphones for Both. Stop the old app yourself before starting another capture session.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("I consent to cloud audio processing and possible API charges", isOn: $consent)
                    }.padding(8)
                }.disabled(worker.running)
                GroupBox("Uzbek → English at your cursor · ⌘Space") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Enable for this launch, focus an editable text caret, press ⌘Space and speak Uzbek. Press ⌘Space again to finish. Google processes microphone audio (API charges); 60s recording / 15s final-turn limit. No Send/Return event. Same English translation model, not a guarantee of perfect wording.").font(.caption)
                        HStack {
                            Button("Microphone access") { permissions.request(source: "microphone") }.disabled(worker.running)
                            Button("Accessibility access", action: dictation.requestAccessibility).disabled(worker.running)
                            Button("Check access", action: permissions.refresh).disabled(worker.running)
                        }
                        HStack {
                            Button(dictation.armed ? "Disable ⌘Space" : "Enable ⌘Space") {
                                if dictation.armed { dictation.disarm() }
                                else { dictation.arm(consent: consent, credentialsValid: credentials.valid, microphoneReady: permissions.microphoneGranted) }
                            }.disabled(!dictation.armed && (worker.running || meetingFiles.busy || !consent || !credentials.valid))
                            Button("Cancel dictation") { dictation.cancel() }.disabled(!dictation.active)
                            Button("Copy English draft") { dictation.copyDraft(to: .general) }.disabled(dictation.draft.isEmpty)
                        }
                        Text(dictation.status).font(.callout)
                        if !dictation.draft.isEmpty { Text(dictation.draft).font(.callout).textSelection(.enabled) }
                        Text("Password fields, selections, terminal apps, changed focus/caret, multiline/control text or unsupported apps are rejected; draft remains for explicit Copy. Dictation is not saved to meeting files. Nothing is typed until a successful final turn; captions and dictation cannot capture simultaneously.").font(.caption).foregroundStyle(.secondary)
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("3 · Meeting files") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Save transcript and translation for each meeting", isOn: $preferences.appearance.saveMeetings)
                            .disabled(worker.running || meetingFiles.busy)
                        Text(preferences.appearance.meetingFolder).font(.caption).textSelection(.enabled)
                        HStack {
                            Button("Choose folder…", action: chooseMeetingFolder).disabled(worker.running || meetingFiles.busy)
                            Button("Show last meeting", action: meetingFiles.reveal).disabled(meetingFiles.lastFolder == nil)
                        }
                        Text("Plaintext files stay in the selected folder. No audio recording. Choose a private local folder; a cloud-synced folder can upload these files. Clear text only clears the overlay, not saved meetings.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(meetingFiles.status).font(.callout).textSelection(.enabled)
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button(dictation.active ? "Cancel dictation" : (worker.running ? "Stop captions" : "Start captions")) { if dictation.active { dictation.cancel() } else if worker.running { worker.stop() } else { start(consent) } }
                        .buttonStyle(.borderedProminent).disabled(!worker.running && (meetingFiles.busy || !consent || !credentials.valid || !permissions.canStart(source: preferences.appearance.source)))
                    Button("Show / hide overlay", action: toggleOverlay)
                    Button("Clear text", action: clear).disabled(worker.running)
                }
                Text(worker.status).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                GroupBox("Appearance — saved automatically") {
                    VStack(spacing: 14) {
                        HStack {
                            Button("Compact layout") { preferences.useCompactLayout() }
                            Text("620 × 190 · 17/20 pt · full scrollback").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                        Text("All original text and translations stay in scrollback until you explicitly Clear text or quit. Scroll up to read history; return to the bottom to follow live captions (macOS 15+). Meeting files keep previous sessions when saving is on. History/file safety limits stop capture instead of silently deleting text.").font(.caption).foregroundStyle(.secondary)
                        sizeSlider("Original", value: $preferences.appearance.originalSize, range: 12...64)
                        sizeSlider("Translation", value: $preferences.appearance.translationSize, range: 12...72)
                        HStack {
                            ColorPicker("Original", selection: color(\.originalColor), supportsOpacity: false)
                            ColorPicker("Translation", selection: color(\.translationColor), supportsOpacity: false)
                            ColorPicker("Background", selection: color(\.backgroundColor), supportsOpacity: false)
                        }
                        sizeSlider("Background opacity", value: $preferences.appearance.opacity, range: 0.1...1, percentage: true)
                        sizeSlider("Window width", value: $preferences.appearance.width, range: 340...1800)
                        sizeSlider("Window height", value: $preferences.appearance.height, range: 140...1200)
                        Toggle("Smooth transitions (respects Reduce Motion)", isOn: $preferences.appearance.animations)
                        Text("Drag anywhere on the overlay, including text. Resize any edge or corner, or use the sliders. Position and size are saved. Overlay contains only original text and translation.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }
                Text("Sentence pairing follows each source’s stream order. Gemini does not send shared sentence IDs; wording/sentence splits can differ. Exact semantic alignment is not guaranteed.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
        .frame(minWidth: 640, minHeight: 560)
        .onChange(of: consent) { _, value in if !value { dictation.disarm() } }
        .onChange(of: credentials.apiKey) { _, _ in consent = false; pasteFailed = false; dictation.disarm() }
        .onChange(of: preferences.appearance.source) { _, _ in consent = false; permissions.refresh() }
        .onChange(of: preferences.appearance.target) { _, _ in consent = false }
        .onChange(of: preferences.appearance.saveMeetings) { _, _ in consent = false }
        .onChange(of: preferences.appearance.meetingFolder) { _, _ in consent = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permissions.refresh() }
    }
    private func chooseMeetingFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.message = "Choose a private folder for plaintext meeting transcripts. No audio is recorded."
        panel.prompt = "Choose folder"
        if panel.runModal() == .OK, let url = panel.url { preferences.appearance.meetingFolder = url.path }
    }
    private func sizeSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, percentage: Bool = false) -> some View {
        HStack {
            Text(title).frame(width: 150, alignment: .leading)
            Slider(value: value, in: range)
            Text(percentage ? "\(Int(value.wrappedValue * 100))%" : "\(Int(value.wrappedValue))")
                .monospacedDigit().frame(width: 48, alignment: .trailing)
        }
    }
}
