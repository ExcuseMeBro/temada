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
    var body: some View {
        let a = preferences.appearance
        let rows = Array(captions.rows.suffix(a.visiblePairs))
        let animation: Animation? = a.animations && !reduceMotion ? .easeOut(duration: 0.18) : nil
        // Deliberately NO controls, status, source headers or placeholders here.
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 17) {
                    ForEach(rows) { pair in
                        VStack(alignment: .leading, spacing: 5) {
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
                .padding(20)
                .animation(animation, value: rows.map(\.id))
            }
            .onChange(of: captions.rows) { _, rows in
                if let last = rows.last { withAnimation(animation) { proxy.scrollTo(last.id, anchor: .bottom) } }
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
    @State private var consent = false
    var toggleOverlay: () -> Void
    var clear: () -> Void
    var start: (Bool) -> Void
    private func color(_ path: WritableKeyPath<Appearance, String>) -> Binding<Color> {
        Binding(get: { Color(hex: preferences.appearance[keyPath: path]) }, set: { preferences.appearance[keyPath: path] = $0.hex })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Meeting Captions").font(.largeTitle.bold())
                Text("Native overlay · EN / RU / UZ").foregroundStyle(.secondary)
                GroupBox("Audio & Gemini Live") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TextField("Existing .env file path", text: $preferences.appearance.envPath)
                            Button("Choose…") { chooseFile() }
                        }
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
                HStack {
                    Button(worker.running ? "Stop captions" : "Start captions") { if worker.running { worker.stop() } else { start(consent) } }
                        .buttonStyle(.borderedProminent).disabled(!worker.running && !consent)
                    Button("Show / hide overlay", action: toggleOverlay)
                    Button("Clear text", action: clear).disabled(worker.running)
                }
                Text(worker.status).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                GroupBox("Appearance — saved automatically") {
                    VStack(spacing: 14) {
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
                        Stepper("Visible pairs: \(preferences.appearance.visiblePairs)", value: $preferences.appearance.visiblePairs, in: 1...12)
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
        .onChange(of: preferences.appearance.envPath) { _, _ in consent = false }
        .onChange(of: preferences.appearance.source) { _, _ in consent = false }
        .onChange(of: preferences.appearance.target) { _, _ in consent = false }
    }
    private func sizeSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, percentage: Bool = false) -> some View {
        HStack {
            Text(title).frame(width: 150, alignment: .leading)
            Slider(value: value, in: range)
            Text(percentage ? "\(Int(value.wrappedValue * 100))%" : "\(Int(value.wrappedValue))")
                .monospacedDigit().frame(width: 48, alignment: .trailing)
        }
    }
    private func chooseFile() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url { preferences.appearance.envPath = url.path }
    }
}
