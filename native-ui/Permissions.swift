import AppKit
import AVFoundation
import Combine
import CoreGraphics
import Security

// No capture, prompt or network call during construction or refresh.
@MainActor protocol CaptureAuthorization {
    func screenAllowed() -> Bool
    func microphoneStatus() -> AVAuthorizationStatus
    func requestScreen(_ completion: @escaping @MainActor (Bool) -> Void)
    func requestMicrophone(_ completion: @escaping @MainActor (Bool) -> Void)
}
@MainActor final class SystemCaptureAuthorization: CaptureAuthorization {
    func screenAllowed() -> Bool { CGPreflightScreenCaptureAccess() }
    func microphoneStatus() -> AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }
    func requestScreen(_ completion: @escaping @MainActor (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let granted = CGRequestScreenCaptureAccess()
            DispatchQueue.main.async { completion(granted) }
        }
    }
    func requestMicrophone(_ completion: @escaping @MainActor (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }
}
enum AppIdentity {
    static var certificateSigned: Bool {
        guard Bundle.main.bundleIdentifier == "dev.bro.mclbb" else { return false }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String else { return false }
        return !team.isEmpty
    }
}
@MainActor final class RecordingPermissions: ObservableObject {
    @Published private(set) var screenGranted = false
    @Published private(set) var microphoneGranted = false
    @Published private(set) var requesting = false
    @Published private(set) var message = ""
    let certificateSigned: Bool
    private let backend: CaptureAuthorization
    private var requestedScreen = false
    private var requestedMicrophone = false
    init(backend: CaptureAuthorization? = nil, certificateSigned: Bool? = nil) {
        self.backend = backend ?? SystemCaptureAuthorization()
        self.certificateSigned = certificateSigned ?? AppIdentity.certificateSigned
        refresh()
    }
    func refresh() {
        screenGranted = backend.screenAllowed()
        microphoneGranted = backend.microphoneStatus() == .authorized
        if !certificateSigned { message = "Unsigned test build. Open the certificate-signed Temada.app; access requests and capture are disabled here." }
    }
    func canStart(source: String) -> Bool {
        guard certificateSigned else { return false }
        switch source {
        case "system": return screenGranted
        case "microphone": return microphoneGranted
        case "both": return screenGranted && microphoneGranted
        default: return false
        }
    }
    func request(source: String) {
        guard certificateSigned, !requesting else { return }
        refresh()
        guard ["system", "microphone", "both"].contains(source) else { return }
        // Only this explicit Settings button requests OS permission. Start never does.
        if source != "microphone", !screenGranted {
            guard !requestedScreen else { showSettingsHint(); return }
            requestedScreen = true; requesting = true
            backend.requestScreen { [weak self] _ in
                guard let self else { return }
                self.requesting = false; self.refresh()
                // Trust the actual preflight, not a stale request callback result.
                self.message = self.screenGranted ? "System audio access granted. Request again if microphone access is also needed." : self.settingsHint
            }
        } else if source != "system", !microphoneGranted {
            guard !requestedMicrophone, backend.microphoneStatus() == .notDetermined else { showSettingsHint(); return }
            requestedMicrophone = true; requesting = true
            backend.requestMicrophone { [weak self] _ in
                guard let self else { return }
                self.requesting = false; self.refresh()
                self.message = self.microphoneGranted ? "Microphone access granted." : self.settingsHint
            }
        } else { message = "Required macOS access is ready. Confirm cloud consent, then Start captions." }
    }
    private var settingsHint: String {
        "Open Privacy Settings and enable Temada (older entries may say MCLBB; not Native v2/v3/v4). If macOS requires a restart, quit and reopen Temada yourself. No permission resets are performed."
    }
    private func showSettingsHint() { message = settingsHint }
    func openSettings(source: String) {
        let pane = source == "microphone" || (source == "both" && screenGranted && !microphoneGranted) ? "Privacy_Microphone" : "Privacy_ScreenCapture"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}
