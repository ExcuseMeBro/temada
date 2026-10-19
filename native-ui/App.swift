import AppKit
import SwiftUI
import Combine

@MainActor final class NativeDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let preferences = Preferences()
    let captions = Captions()
    let worker = StreamingWorker()
    let permissions = RecordingPermissions()
    let credentials = APICredentials()
    let meetingFiles = MeetingFiles()
    private var statusItem: NSStatusItem!
    private var overlay: NSPanel!
    private var settings: NSWindow?
    private var startItem: NSMenuItem!
    private var statusMenuItem: NSMenuItem!
    private var observers = Set<AnyCancellable>()
    private var applyingFrame = false
    private var pendingQuit = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        overlay = CaptionPanel(contentRect: NSRect(x: 0, y: 0, width: preferences.appearance.width, height: preferences.appearance.height), styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        overlay.title = "Temada — subtitles"
        overlay.isReleasedWhenClosed = false; overlay.level = .floating
        overlay.isOpaque = false; overlay.backgroundColor = .clear; overlay.hasShadow = true
        overlay.isMovableByWindowBackground = true; overlay.hidesOnDeactivate = false
        overlay.acceptsMouseMovedEvents = true
        overlay.becomesKeyOnlyIfNeeded = true; overlay.minSize = NSSize(width: 340, height: 140)
        overlay.maxSize = NSSize(width: 1800, height: 1200)
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlay.contentView = captionHostingView(preferences: preferences, captions: captions)
        overlay.delegate = self
        applyFrame(preferences.appearance, restorePosition: true)
        overlay.orderFrontRegardless()
        createMenu()
        preferences.$appearance.debounce(for: .milliseconds(60), scheduler: RunLoop.main).sink { [weak self] value in self?.applyFrame(value, restorePosition: false) }.store(in: &observers)
        worker.$running.sink { [weak self] running in
            self?.startItem.title = running ? "Stop captions" : "Start captions…"
            self?.statusItem.button?.image = self?.menuImage(running: running)
            self?.statusItem.button?.toolTip = running ? "Temada · Captions running" : "Temada"
        }.store(in: &observers)
        worker.$status.sink { [weak self] message in self?.statusMenuItem.title = String(message.prefix(90)) }.store(in: &observers)
        meetingFiles.onFailure = { [weak self] in self?.worker.fail("Meeting file write failed. Partial files retained.") }
        worker.onFrames = { [weak self] frames in
            guard let self else { return }
            do { try self.meetingFiles.record(frames) }
            catch { self.worker.fail("Meeting save limit/write failure. Partial files retained."); return }
            do { for frame in frames { try self.captions.consume(frame) } }
            catch { self.worker.fail("Caption alignment/size limit reached. Stop and clear before restarting.") }
        }
        worker.onStopped = { [weak self] in
            guard let self else { return }
            self.finishMeeting()
        }
        // Settings are separate from the subtitle panel, never auto-start capture.
        showSettings()
    }
    private func createMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = menuImage(running: false)
        statusItem.button?.toolTip = "Temada"
        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Ready", action: nil, keyEquivalent: ""); statusMenuItem.isEnabled = false; menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        startItem = item("Start captions…", #selector(toggleCapture), key: "s"); menu.addItem(startItem)
        menu.addItem(item("Show / hide subtitles", #selector(toggleOverlay), key: "h"))
        menu.addItem(item("Clear text", #selector(clearText), key: "k"))
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(item("Show last meeting files", #selector(showMeetingFiles), key: "m"))
        menu.addItem(.separator()); menu.addItem(item("Quit Temada", #selector(quit), key: "q"))
        statusItem.menu = menu
    }
    private func menuImage(running: Bool) -> NSImage? {
        guard let logo = NSImage(named: NSImage.Name("Temada")) else { return NSImage(systemSymbolName: running ? "captions.bubble.fill" : "captions.bubble", accessibilityDescription: "Temada") }
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.lockFocus(); logo.draw(in: NSRect(x: 0, y: 0, width: 20, height: 20))
        if running { NSColor.systemGreen.setFill(); NSBezierPath(ovalIn: NSRect(x: 15, y: 0, width: 5, height: 5)).fill() }
        image.unlockFocus(); return image
    }
    private func item(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let value = NSMenuItem(title: title, action: action, keyEquivalent: key); value.target = self; return value
    }
    @objc func showSettings() {
        if settings == nil {
            let view = NativeSettings(preferences: preferences, worker: worker, permissions: permissions, credentials: credentials, meetingFiles: meetingFiles,
                toggleOverlay: { [weak self] in self?.toggleOverlay() }, clear: { [weak self] in self?.clearText() }, start: { [weak self] consent in self?.startCapture(consent: consent) })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 760), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Temada — Settings"; window.isReleasedWhenClosed = false
            window.isRestorable = false // Never archive a window containing API credentials.
            window.contentView = NSHostingView(rootView: view); window.center(); settings = window
        }
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }
    @objc func toggleOverlay() { if overlay.isVisible { overlay.orderOut(nil) } else { overlay.orderFrontRegardless() } }
    @objc func clearText() { if !worker.running { captions.clear() } }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { menuItem.action != #selector(clearText) || !worker.running }
    @objc func toggleCapture() { if worker.running { worker.stop() } else { showSettings() } }
    private func startCapture(consent: Bool) {
        guard consent, credentials.valid, !worker.running, !meetingFiles.busy else { return }
        permissions.refresh()
        guard permissions.canStart(source: preferences.appearance.source) else { showSettings(); return }
        do { try meetingFiles.start(appearance: preferences.appearance) }
        catch { worker.fail("Cannot create private meeting files. Choose another folder or turn saving off."); return }
        captions.clear(); overlay.orderFrontRegardless()
        worker.start(appearance: preferences.appearance, credentials: credentials, consent: consent)
        if worker.running { settings?.orderOut(nil) } else { finishMeeting() }
    }
    @objc func showMeetingFiles() { meetingFiles.reveal() }
    private func finishMeeting() {
        meetingFiles.finish { [weak self] okay in
            guard let self else { return }
            if self.pendingQuit {
                self.pendingQuit = false; NSApp.reply(toApplicationShouldTerminate: okay)
                if !okay { self.showSettings() }
            }
        }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard worker.running || meetingFiles.busy else { return .terminateNow }
        pendingQuit = true; worker.stop()
        // Never force-kill an uncertain worker; keep app available if cancellation fails.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.pendingQuit else { return }
            self.pendingQuit = false; NSApp.reply(toApplicationShouldTerminate: false)
        }
        return .terminateLater
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    private func applyFrame(_ a: Appearance, restorePosition: Bool) {
        guard let overlay else { return }
        applyingFrame = true; defer { applyingFrame = false }
        var frame = overlay.frame
        frame.size = NSSize(width: a.width, height: a.height)
        if restorePosition {
            if let x = a.x, let y = a.y { frame.origin = NSPoint(x: x, y: y) }
            else if let screen = NSScreen.main?.visibleFrame { frame.origin = NSPoint(x: screen.midX - frame.width / 2, y: screen.minY + 80) }
        }
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }), let screen = NSScreen.main?.visibleFrame {
            frame.origin = NSPoint(x: screen.minX + 30, y: screen.minY + 60)
        }
        if overlay.frame != frame { overlay.setFrame(frame, display: true) }
    }
    func windowDidResize(_ notification: Notification) { rememberFrame(notification) }
    func windowDidMove(_ notification: Notification) { rememberFrame(notification) }
    private func rememberFrame(_ notification: Notification) {
        guard !applyingFrame, let window = notification.object as? NSPanel, window === overlay else { return }
        let frame = window.frame
        var a = preferences.appearance
        guard abs(a.width - frame.width) > 0.5 || abs(a.height - frame.height) > 0.5 || a.x != frame.minX || a.y != frame.minY else { return }
        a.width = frame.width; a.height = frame.height; a.x = frame.minX; a.y = frame.minY
        preferences.appearance = a
    }
}
@main struct NativeMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") { NativeTests.run(); return }
        if CommandLine.arguments.contains("--verify-identity") {
            guard AppIdentity.certificateSigned else { fputs("IDENTITY: FAIL — signed Temada bundle required\n", stderr); exit(1) }
            guard Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Temada",
                  Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String == "Temada",
                  NSImage(named: NSImage.Name("Temada"))?.isValid == true else { fputs("BRAND: FAIL — Temada name/icon missing\n", stderr); exit(1) }
            print("IDENTITY: PASS — certificate-signed dev.bro.mclbb; BRAND: PASS — Temada name/icon"); return
        }
        let app = NSApplication.shared
        let delegate = NativeDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
