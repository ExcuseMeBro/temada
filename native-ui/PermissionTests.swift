import AVFoundation

@MainActor private final class FakeCaptureAuthorization: CaptureAuthorization {
    var screen = false
    var microphone: AVAuthorizationStatus = .notDetermined
    var screenRequests = 0, microphoneRequests = 0
    var screenCompletion: (@MainActor (Bool) -> Void)?
    var microphoneCompletion: (@MainActor (Bool) -> Void)?
    func screenAllowed() -> Bool { screen }
    func microphoneStatus() -> AVAuthorizationStatus { microphone }
    func requestScreen(_ completion: @escaping @MainActor (Bool) -> Void) { screenRequests += 1; screenCompletion = completion }
    func requestMicrophone(_ completion: @escaping @MainActor (Bool) -> Void) { microphoneRequests += 1; microphoneCompletion = completion }
}
@MainActor enum PermissionTests {
    static func run() {
        let b = FakeCaptureAuthorization()
        let p = RecordingPermissions(backend: b, certificateSigned: true)
        precondition(b.screenRequests == 0 && b.microphoneRequests == 0)
        precondition(!p.canStart(source: "system") && !p.canStart(source: "microphone") && !p.canStart(source: "both"))
        p.request(source: "unknown"); precondition(b.screenRequests == 0)
        p.request(source: "both"); p.request(source: "both")
        precondition(p.requesting && b.screenRequests == 1 && b.microphoneRequests == 0)
        // Even a stale 'granted' callback must not bypass current denied preflight.
        b.screenCompletion?(true)
        precondition(!p.requesting && !p.canStart(source: "system"))
        p.request(source: "both"); precondition(b.screenRequests == 1 && b.microphoneRequests == 0)
        b.screen = true; p.refresh()
        precondition(p.canStart(source: "system") && !p.canStart(source: "both") && !p.canStart(source: "unknown"))
        p.request(source: "both"); p.request(source: "both")
        precondition(b.microphoneRequests == 1 && p.requesting)
        b.microphoneCompletion?(false)
        p.request(source: "microphone"); precondition(b.microphoneRequests == 1)
        b.microphone = .authorized; p.refresh()
        precondition(p.canStart(source: "both"))
        b.screen = false; p.refresh()
        precondition(p.canStart(source: "microphone") && !p.canStart(source: "both"))
        for denied: AVAuthorizationStatus in [.denied, .restricted] {
            let b = FakeCaptureAuthorization(); b.microphone = denied
            let p = RecordingPermissions(backend: b, certificateSigned: true)
            p.request(source: "microphone"); p.request(source: "microphone")
            precondition(!p.canStart(source: "microphone") && b.microphoneRequests == 0)
        }
        let unsignedBackend = FakeCaptureAuthorization(); unsignedBackend.screen = true; unsignedBackend.microphone = .authorized
        let unsigned = RecordingPermissions(backend: unsignedBackend, certificateSigned: false)
        for source in ["system", "microphone", "both"] {
            unsigned.request(source: source); precondition(!unsigned.canStart(source: source))
        }
        precondition(unsignedBackend.screenRequests == 0 && unsignedBackend.microphoneRequests == 0)
        print("PERMISSION_SELFTEST: PASS — no implicit prompt, source gates, once-only requests, stale callback, denial/restriction, unsigned rejection")
    }
}
