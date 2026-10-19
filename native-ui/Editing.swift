import AppKit

// Accessory apps still need an application Edit menu for responder-chain shortcuts.
@MainActor func applicationEditingMenu() -> NSMenu {
    let main = NSMenu()
    let application = NSMenuItem(title: "Temada", action: nil, keyEquivalent: "")
    let appMenu = NSMenu(title: "Temada")
    let quit = NSMenuItem(title: "Quit Temada", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    quit.target = NSApplication.shared; appMenu.addItem(quit)
    application.submenu = appMenu; main.addItem(application)
    let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    let edit = NSMenu(title: "Edit")
    for (title, action, key) in [("Undo", Selector(("undo:")), "z"), ("Redo", Selector(("redo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = title == "Redo" ? [.command, .shift] : .command
        // A nil target resolves the focused native text editor, including SecureField.
        item.target = nil; edit.addItem(item)
    }
    editItem.submenu = edit; main.addItem(editItem)
    return main
}

@MainActor enum EditingTests {
    static func run() {
        _ = NSApplication.shared
        let menu = applicationEditingMenu()
        guard let edit = menu.items.first(where: { $0.title == "Edit" })?.submenu,
              let paste = edit.items.first(where: { $0.action == #selector(NSText.paste(_:)) }) else {
            fputs("EDITING_SELFTEST: FAIL — missing responder-chain Paste / Command-V\n", stderr); exit(1)
        }
        precondition(paste.keyEquivalent == "v" && paste.keyEquivalentModifierMask == .command && paste.target == nil)
        for (key, action) in [("x", #selector(NSText.cut(_:))), ("c", #selector(NSText.copy(_:))), ("a", #selector(NSText.selectAll(_:)))] {
            precondition(edit.items.contains { $0.keyEquivalent == key && $0.action == action && $0.target == nil })
        }
        // Only a private synthetic pasteboard: never read or overwrite the user's clipboard.
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let credentials = APICredentials()
        board.setString("  synthetic-test-key-123\n", forType: .string)
        precondition(credentials.pasteKey(from: board) && credentials.apiKey == "synthetic-test-key-123" && credentials.valid)
        board.clearContents(); board.setString(String(repeating: "x", count: 1025), forType: .string)
        precondition(!credentials.pasteKey(from: board) && credentials.apiKey == "synthetic-test-key-123")
        board.clearContents(); board.setString("invalid key", forType: .string)
        precondition(!credentials.pasteKey(from: board) && credentials.apiKey == "synthetic-test-key-123")
        board.clearContents()
        precondition(!credentials.pasteKey(from: board) && credentials.apiKey == "synthetic-test-key-123")
        print("EDITING_SELFTEST: PASS — native Command-V/X/C/A responder actions; explicit private-board paste, trim/bounds/rejection; no user clipboard access")
    }
}
