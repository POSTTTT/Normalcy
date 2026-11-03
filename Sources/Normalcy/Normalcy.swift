import AppKit
import Carbon
import SwiftUI

// Commands (default triggers, editable in Settings):
//   o <app>        open/launch app            e.g. o Safari
//   b <app>        switch to running app      e.g. b saf
//   d <1-9|h|l>    go to desktop N / left / right
//   m <1-9|h|l>    move focused window to desktop N / left / right
//   h l k j        window: left / right / top / bottom half
//   f c            window: full / center
//   set            open settings
enum Command: Equatable {
    case open(String)
    case focus(String)
    case ctrlKey(CGKeyCode)
    case moveToDesktop(CGKeyCode)
    case layout(CGRect) // fractions of the screen, top-left origin
    case settings

    static let digitKeys: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25] // kVK_ANSI_1...9

    static func desktopKey(_ arg: String) -> CGKeyCode? {
        if arg == "h" { return 123 }
        if arg == "l" { return 124 }
        if let n = Int(arg), (1...9).contains(n) { return digitKeys[n - 1] }
        return nil
    }

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
        case .desktop: return desktopKey(arg).map { .ctrlKey($0) }
        case .move: return desktopKey(arg).map { .moveToDesktop($0) }
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

final class App: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 780),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let palette = Palette()
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
        palette.submit = { [weak self] text in
            let cmd = Command.parse(text, Store.shared.defs)
            self?.hide()
            if let cmd { self?.run(cmd) } else { NSSound.beep() }
        }
        palette.cancel = { [weak self] in self?.hide() }
        panel.contentView = NSHostingView(rootView: PaletteView(model: palette))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // SwiftUI draws its own; the window shadow would outline the empty area
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
        palette.text = ""
        palette.desktops = Desktops.read()
        if let s = NSScreen.main?.frame {
            panel.setFrameOrigin(NSPoint(x: s.midX - panel.frame.width / 2,
                                         y: s.maxY - s.height * 0.2 - panel.frame.height))
        }
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { self.palette.focusToken += 1 }
    }

    func hide() { panel.orderOut(nil) }

    func windowDidResignKey(_ n: Notification) { hide() }

    func run(_ cmd: Command) {
        switch cmd {
        case .open(let name):
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-a", name])
        case .focus(let q):
            NSWorkspace.shared.runningApplications.first {
                $0.activationPolicy == .regular && ($0.localizedName ?? "").lowercased().hasPrefix(q.lowercased())
            }?.activate()
        case .ctrlKey(let key):
            pressCtrl(key)
        case .moveToDesktop(let key):
            moveWindow(toDesktop: key)
        case .layout(let f):
            place(f)
        case .settings:
            openSettings()
        }
    }

    @discardableResult
    func pressCtrl(_ key: CGKeyCode) -> Bool {
        // Needs "Switch to Desktop N" / "Move left/right a space" enabled in
        // System Settings > Keyboard > Keyboard Shortcuts > Mission Control.
        // Without Accessibility trust, posted events are silently dropped.
        if !AXIsProcessTrusted() { NSSound.beep(); print("Normalcy: grant Accessibility permission"); return false }
        // Real arrow key events carry fn + numpad flags; Mission Control ignores them otherwise.
        let flags: CGEventFlags = key == 123 || key == 124
            ? [.maskControl, .maskSecondaryFn, .maskNumericPad] : .maskControl
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
        return true
    }

    // No public API moves a window between spaces. Instead: hold the mouse down on the
    // title bar, switch desktop, release — macOS carries a dragged window along.
    func moveWindow(toDesktop key: CGKeyCode) {
        guard AXIsProcessTrusted(), let w = focusedWindow(), let grab = titleBarPoint(w) else { NSSound.beep(); return }
        let restore = CGEvent(source: nil)?.location ?? grab
        postMouse(.mouseMoved, grab)
        postMouse(.leftMouseDown, grab)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.pressCtrl(key)
            // Wait for the space-switch animation before letting go.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.postMouse(.leftMouseUp, grab)
                CGWarpMouseCursorPosition(restore)
            }
        }
    }

    func postMouse(_ type: CGEventType, _ p: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    // shortcut: assumes empty title bar just right of the green button; apps with custom
    // toolbars there (e.g. a sidebar button) won't drag. Upgrade: probe with AXUIElementCopyElementAtPosition.
    func titleBarPoint(_ w: AXUIElement) -> CGPoint? {
        var zoom: CFTypeRef?
        if AXUIElementCopyAttributeValue(w, kAXZoomButtonAttribute as CFString, &zoom) == .success,
           let zoom, let f = axFrame(zoom as! AXUIElement) {
            return CGPoint(x: f.maxX + 8, y: f.midY)
        }
        return axFrame(w).map { CGPoint(x: $0.minX + 90, y: $0.minY + 12) }
    }

    func axFrame(_ e: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &s) == .success,
              let p, let s else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &origin)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    func focusedWindow() -> AXUIElement? {
        guard let app = target else { return nil }
        var win: CFTypeRef?
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        guard AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &win) == .success,
              let win else { return nil }
        return (win as! AXUIElement)
    }

    func place(_ f: CGRect) {
        // shortcut: uses the screen with the panel, not the window's own screen; fix for multi-monitor
        guard let w = focusedWindow(), let screen = NSScreen.main, let primary = NSScreen.screens.first else { return }
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
        if CommandLine.arguments.contains("--desktops") { print(Desktops.read()); return }
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
        precondition(Command.parse("m 3", d) == .moveToDesktop(20))
        precondition(Command.parse("m h", d) == .moveToDesktop(123))
        precondition(Command.parse("m", d) == nil)
        precondition(Command.parse("h", d) == .layout(CGRect(x: 0, y: 0, width: 0.5, height: 1)))
        precondition(Command.parse("set", d) == .settings)
        precondition(Command.parse("o", d) == nil)
        precondition(Command.parse("", d) == nil)
        // Renamed trigger works, old one doesn't; hidden command doesn't run.
        var custom = d
        custom[custom.firstIndex { $0.id == "open" }!].trigger = "open"
        custom[custom.firstIndex { $0.id == "left" }!].enabled = false
        precondition(Command.parse("open Safari", custom) == .open("Safari"))
        precondition(Command.parse("o Safari", custom) == nil)
        precondition(Command.parse("h", custom) == nil)

        // Palette: filtering and Enter on the selected row.
        let p = Palette()
        p.defs = { d }
        var submitted: String?
        p.submit = { submitted = $0 }
        precondition(p.matches.count == d.count)
        p.text = "c"
        precondition(p.matches.first?.id == "center") // exact trigger first
        p.text = "half"
        precondition(Set(p.matches.map(\.id)) == ["left", "right", "top", "bottom"])
        p.text = "o Saf"
        precondition(p.matches.map(\.id) == ["open"])
        p.text = "o"
        p.enter()
        precondition(p.text == "o " && submitted == nil) // needs an app name, so fill trigger
        p.text = "f"
        p.enter()
        precondition(submitted == "f")
        p.text = "o Safari"
        p.enter()
        precondition(submitted == "o Safari")

        // Desktops: full-screen spaces (type 4) aren't numbered.
        let fake: [[String: Any]] = [[
            "Current Space": ["ManagedSpaceID": 7],
            "Spaces": [["ManagedSpaceID": 3, "type": 0], ["ManagedSpaceID": 9, "type": 4], ["ManagedSpaceID": 7, "type": 0]],
        ]]
        precondition(Desktops.parse(fake) == Desktops(count: 2, current: 2))
        precondition(Desktops.parse([]) == Desktops())
        p.desktops = Desktops(count: 4, current: 2)
        p.text = "d"
        precondition(p.desktopCommand?.id == "desktop" && p.desktopTarget == nil)
        p.text = "m h"
        precondition(p.desktopCommand?.id == "move" && p.desktopTarget == 1)
        p.text = "d 4"
        precondition(p.desktopTarget == 4)
        p.text = "f"
        precondition(p.desktopCommand == nil)
        print("selftest ok")
    }
}
