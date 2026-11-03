import AppKit
import Carbon
import SwiftUI

// Commands (default triggers, editable in Settings):
//   o <app>        open/launch app            e.g. o Safari
//   b <app>        switch to running app      e.g. b saf
//   d <1-9|h|l>    go to desktop N / left / right
//   h l k j        window: left / right / top / bottom half
//   f c            window: full / center
//   set            open settings
enum Command: Equatable {
    case open(String)
    case focus(String)
    case ctrlKey(CGKeyCode)
    case layout(CGRect) // fractions of the screen, top-left origin
    case settings

    static let digitKeys: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25] // kVK_ANSI_1...9

    static func parse(_ input: String, _ defs: [CommandDef]) -> Command? {
        let s = input.trimmingCharacters(in: .whitespaces)
        let parts = s.split(separator: " ", maxSplits: 1).map(String.init)
        guard let head = parts.first,
              let def = defs.first(where: { $0.enabled && $0.trigger == head }),
              let action = Action(rawValue: def.id) else { return nil }
        let arg = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        switch action {
        case .open: return arg.isEmpty ? nil : .open(arg)
        case .focus: return arg.isEmpty ? nil : .focus(arg)
        case .desktop:
            if arg == "h" { return .ctrlKey(123) }
            if arg == "l" { return .ctrlKey(124) }
            if let n = Int(arg), (1...9).contains(n) { return .ctrlKey(digitKeys[n - 1]) }
            return nil
        case .left: return .layout(CGRect(x: 0, y: 0, width: 0.5, height: 1))
        case .right: return .layout(CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        case .top: return .layout(CGRect(x: 0, y: 0, width: 1, height: 0.5))
        case .bottom: return .layout(CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
        case .full: return .layout(CGRect(x: 0, y: 0, width: 1, height: 1))
        case .center: return .layout(CGRect(x: 0.15, y: 0.1, width: 0.7, height: 0.8))
        case .settings: return .settings
        }
    }
}

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class App: NSObject, NSApplicationDelegate, NSTextFieldDelegate, NSWindowDelegate {
    let panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 48),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let field = NSTextField()
    var hotKey: EventHotKeyRef?
    var target: NSRunningApplication?
    var statusItem: NSStatusItem?
    lazy var settingsWindow: NSWindow = {
        let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        w.title = "Normalcy Settings"
        w.isReleasedWhenClosed = false
        return w
    }()

    func applicationDidFinishLaunching(_ n: Notification) {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        buildPanel()
        registerHotKey()
        buildStatusItem()
    }

    func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Normalcy")
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Normalcy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc func openSettings() {
        NSApp.activate()
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    func buildPanel() {
        let bg = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 10
        field.frame = bg.bounds.insetBy(dx: 14, dy: 10)
        field.autoresizingMask = [.width, .height]
        field.font = .monospacedSystemFont(ofSize: 20, weight: .regular)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        bg.addSubview(field)
        panel.contentView = bg
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
    }

    // Option+Space. Carbon hotkeys need no Accessibility permission.
    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ctx in
            Unmanaged<App>.fromOpaque(ctx!).takeUnretainedValue().show()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey),
                            EventHotKeyID(signature: OSType(0x4E524D4C), id: 1),
                            GetApplicationEventTarget(), 0, &hotKey)
    }

    func show() {
        target = NSWorkspace.shared.frontmostApplication
        field.stringValue = ""
        field.placeholderString = Store.shared.defs.filter(\.enabled).map(\.trigger).joined(separator: "  ")
        if let s = NSScreen.main?.frame {
            panel.setFrameOrigin(NSPoint(x: s.midX - panel.frame.width / 2, y: s.maxY - s.height * 0.3))
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    func hide() { panel.orderOut(nil) }

    func windowDidResignKey(_ n: Notification) { hide() }

    func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            let cmd = Command.parse(field.stringValue, Store.shared.defs)
            hide()
            if let cmd { run(cmd) } else { NSSound.beep() }
            return true
        }
        if sel == #selector(NSResponder.cancelOperation(_:)) { hide(); return true }
        return false
    }

    func run(_ cmd: Command) {
        switch cmd {
        case .open(let name):
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-a", name])
        case .focus(let q):
            NSWorkspace.shared.runningApplications.first {
                $0.activationPolicy == .regular && ($0.localizedName ?? "").lowercased().hasPrefix(q.lowercased())
            }?.activate()
        case .ctrlKey(let key):
            // Needs "Switch to Desktop N" / "Move left/right a space" enabled in
            // System Settings > Keyboard > Keyboard Shortcuts > Mission Control.
            // Without Accessibility trust, posted events are silently dropped.
            if !AXIsProcessTrusted() { NSSound.beep(); print("Normalcy: grant Accessibility permission"); return }
            // Real arrow key events carry fn + numpad flags; Mission Control ignores them otherwise.
            let flags: CGEventFlags = key == 123 || key == 124
                ? [.maskControl, .maskSecondaryFn, .maskNumericPad] : .maskControl
            let src = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
                e?.flags = flags
                e?.post(tap: .cghidEventTap)
            }
        case .layout(let f):
            place(f)
        case .settings:
            openSettings()
        }
    }

    func place(_ f: CGRect) {
        // shortcut: uses the screen with the panel, not the window's own screen; fix for multi-monitor
        guard let app = target, let screen = NSScreen.main, let primary = NSScreen.screens.first else { return }
        var win: CFTypeRef?
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        guard AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &win) == .success,
              let win else { return }
        let w = win as! AXUIElement
        let v = screen.visibleFrame
        // AX uses top-left origin of the primary screen; AppKit uses bottom-left.
        var origin = CGPoint(x: v.minX + v.width * f.minX, y: primary.frame.maxY - v.maxY + v.height * f.minY)
        var size = CGSize(width: v.width * f.width, height: v.height * f.height)
        AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin)!)
        AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
    }
}

@main
enum Main {
    static let app = App()

    static func main() {
        if CommandLine.arguments.contains("--selftest") { selfTest(); return }
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.delegate = app
        NSApplication.shared.run()
    }

    static func selfTest() {
        let d = CommandDef.defaults
        precondition(Command.parse("o Safari", d) == .open("Safari"))
        precondition(Command.parse("o Visual Studio Code", d) == .open("Visual Studio Code"))
        precondition(Command.parse("b saf", d) == .focus("saf"))
        precondition(Command.parse("d 2", d) == .ctrlKey(19))
        precondition(Command.parse("d l", d) == .ctrlKey(124))
        precondition(Command.parse("d 0", d) == nil)
        precondition(Command.parse("h", d) == .layout(CGRect(x: 0, y: 0, width: 0.5, height: 1)))
        precondition(Command.parse("set", d) == .settings)
        precondition(Command.parse("o", d) == nil)
        precondition(Command.parse("", d) == nil)
        // Renamed trigger works, old one doesn't; hidden command doesn't run.
        var custom = d
        custom[0].trigger = "open"
        custom[3].enabled = false
        precondition(Command.parse("open Safari", custom) == .open("Safari"))
        precondition(Command.parse("o Safari", custom) == nil)
        precondition(Command.parse("h", custom) == nil)
        print("selftest ok")
    }
}
