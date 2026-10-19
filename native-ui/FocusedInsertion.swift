import AppKit
import ApplicationServices

struct CursorContext: Equatable {
    var pid: pid_t
    var location: Int
    var length: Int
    var role: String
    var secure: Bool
    var editable: Bool
}
enum CursorPolicy {
    static func safeText(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 16000 && !text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) }
    }
    static func safeApplication(_ id: String?) -> Bool {
        guard let id else { return false }
        return !["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "dev.warp.Warp"].contains(id)
    }
    static func permits(before: CursorContext, after: CursorContext, sameElement: Bool, trusted: Bool, ownPID: pid_t) -> Bool {
        trusted && sameElement && before == after && before.pid != ownPID && before.pid > 0 && before.location >= 0 && before.length == 0 && !before.secure && before.editable && ["AXTextField", "AXTextArea"].contains(before.role)
    }
}
// Never reads field contents, clipboard or other applications' keystrokes.
// Only a captured, still-focused editable caret can receive one AX selected-text
// insertion. No keyboard/Paste/Return events or whole-field replacement fallback.
struct FocusedCursor {
    let element: AXUIElement
    let before: CursorContext
    enum Failure: Error { case unavailable }
    private static func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { throw Failure.unavailable }
        return value
    }
    private static func focused() throws -> (AXUIElement, CursorContext) {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication, CursorPolicy.safeApplication(app.bundleIdentifier), app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { throw Failure.unavailable }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.3)
        let raw = try attribute(application, kAXFocusedUIElementAttribute)
        guard CFGetTypeID(raw) == AXUIElementGetTypeID() else { throw Failure.unavailable }
        let element = unsafeBitCast(raw, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.3)
        var owner: pid_t = 0
        guard AXUIElementGetPid(element, &owner) == .success, owner == app.processIdentifier else { throw Failure.unavailable }
        let role = try attribute(element, kAXRoleAttribute) as? String ?? ""
        let subrole = (try? attribute(element, kAXSubroleAttribute)) as? String ?? ""
        let protected = (try? attribute(element, "AXProtectedContent")) as? Bool ?? false
        guard ["AXTextField", "AXTextArea"].contains(role), !protected, subrole != "AXSecureTextField" else { throw Failure.unavailable }
        let rawRange = try attribute(element, kAXSelectedTextRangeAttribute)
        guard CFGetTypeID(rawRange) == AXValueGetTypeID() else { throw Failure.unavailable }
        let value = unsafeBitCast(rawRange, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range) else { throw Failure.unavailable }
        var settable: DarwinBoolean = false
        let editable = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success && settable.boolValue
        return (element, CursorContext(pid: app.processIdentifier, location: range.location, length: range.length, role: role, secure: protected || subrole == "AXSecureTextField", editable: editable))
    }
    static func capture() throws -> Self {
        let (element, context) = try focused()
        guard CursorPolicy.permits(before: context, after: context, sameElement: true, trusted: AXIsProcessTrusted(), ownPID: ProcessInfo.processInfo.processIdentifier) else { throw Failure.unavailable }
        return Self(element: element, before: context)
    }
    func insert(_ text: String) throws {
        guard CursorPolicy.safeText(text) else { throw Failure.unavailable }
        let (current, context) = try Self.focused()
        guard CursorPolicy.permits(before: before, after: context, sameElement: CFEqual(element, current), trusted: AXIsProcessTrusted(), ownPID: ProcessInfo.processInfo.processIdentifier) else { throw Failure.unavailable }
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success else { throw Failure.unavailable }
    }
}
