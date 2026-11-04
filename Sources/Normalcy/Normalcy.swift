import AppKit
import Carbon
import Combine
import SwiftUI

// Commands (default triggers, editable in Settings):
//   o <app>        open/launch app            e.g. o Safari
//   b <app>        switch to running app      e.g. b saf
//   d <1-9|h|l>    go to desktop N / left / right
//   m <1-9|h|l>    move focused window to desktop N / left / right
//   t [h|l|k|j|f|c]   move current tab to a new window, optionally placed with a layout
//   h l k j        window: left / right / top / bottom half
//   f c            window: full / center
//   set            open settings
enum Command: Equatable {
    case open(String)
    case focus(String)
    case ctrlKey(CGKeyCode)
    case moveToDesktop(CGKeyCode)
    case tabToWindow(CGRect?) // optional layout for the new window
    case layout(CGRect) // fractions of the screen, top-left origin
    case settings

    static let digitKeys: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25] // kVK_ANSI_1...9

    // Arrow keys type these symbols; they stand for the matching direction command,
    // whatever its trigger has been renamed to.
    static func arrowAction(_ s: String) -> Action? {
        ["←": .left, "→": .right, "↑": .top, "↓": .bottom][s]
    }

    // Enabled command for a typed word: its trigger, an arrow symbol, or two directions
    // in either order making a corner ("kh" = "hk" = ← ↑ = top-left quarter).
    static func lookup(_ word: String, in defs: [CommandDef]) -> CommandDef? {
        if let d = defs.first(where: { $0.enabled && ($0.trigger == word || arrowAction(word)?.rawValue == $0.id) }) {
            return d
        }
        // An arrow can stand in for its letter inside a trigger: "←3" = "h3" (left third).
        let spelled = word.map { ch in
            arrowAction(String(ch)).flatMap { a in defs.first { $0.id == a.rawValue }?.trigger } ?? String(ch)
        }.joined()
        if spelled != word, let d = defs.first(where: { $0.enabled && $0.trigger == spelled }) { return d }
        guard word.count == 2 else { return nil }
        let corners: [Set<Action>: Action] = [
            [.left, .top]: .topLeft, [.right, .top]: .topRight, [.left, .bottom]: .bottomLeft, [.right, .bottom]: .bottomRight,
        ]
        let dirs = word.compactMap { direction(String($0), in: defs) }
        guard dirs.count == 2, let corner = corners[Set(dirs)] else { return nil }
        return defs.first { $0.enabled && $0.id == corner.rawValue }
    }

    // A single key meaning left/right/top/bottom: an arrow, or that direction key.
    // Works even when the half command itself is switched off.
    static func direction(_ key: String, in defs: [CommandDef]) -> Action? {
        if let a = arrowAction(key) { return a }
        return Action.directions.first { a in defs.first { $0.id == a.rawValue }?.trigger == key }
    }

    static func desktopKey(_ arg: String, _ defs: [CommandDef]) -> CGKeyCode? {
        switch direction(arg, in: defs) {
        case .left: return 123
        case .right: return 124
        default: break
        }
        if let n = Int(arg), (1...9).contains(n) { return digitKeys[n - 1] }
        return nil
    }

    // Fills <left> <right> <up> <down> in help text with the current direction keys.
    static func spell(_ s: String, _ defs: [CommandDef]) -> String {
        zip(["<left>", "<down>", "<up>", "<right>"], Action.directions).reduce(s) { s, p in
            s.replacingOccurrences(of: p.0, with: defs.first { $0.id == p.1.rawValue }?.trigger ?? "")
        }
    }

    static func parse(_ input: String, _ defs: [CommandDef]) -> Command? {
        let s = input.trimmingCharacters(in: .whitespaces)
        let parts = s.split(separator: " ", maxSplits: 1).map(String.init)
        guard let head = parts.first,
              let def = lookup(head, in: defs),
              let action = Action(rawValue: def.id) else { return nil }
        let arg = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        switch action {
        case .open: return arg.isEmpty ? nil : .open(arg)
        case .focus: return arg.isEmpty ? nil : .focus(arg)
        case .desktop: return desktopKey(arg, defs).map { .ctrlKey($0) }
        case .move: return desktopKey(arg, defs).map { .moveToDesktop($0) }
        case .left, .right, .top, .bottom, .full, .center, .leftThird, .centerThird, .rightThird,
             .topLeft, .topRight, .bottomLeft, .bottomRight:
            return layoutRect(action).map { .layout($0) }
        case .tab:
            if arg.isEmpty { return .tabToWindow(nil) }
            // Argument is a window-layout trigger, e.g. "t h" = new window on the left half.
            guard let d = lookup(arg, in: defs),
                  let rect = Action(rawValue: d.id).flatMap(layoutRect) else { return nil }
            return .tabToWindow(rect)
        case .settings: return .settings
        }
    }

    static func layoutRect(_ a: Action) -> CGRect? {
        switch a {
        case .left: CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .right: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .top: CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottom: CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .full: CGRect(x: 0, y: 0, width: 1, height: 1)
        case .center: CGRect(x: 0.15, y: 0.1, width: 0.7, height: 0.8)
        case .leftThird: CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1)
        case .centerThird: CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .rightThird: CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .topLeft: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        default: nil
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
    let preview = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    var hotKey: EventHotKeyRef?
    var subs = Set<AnyCancellable>()
    var target: NSRunningApplication?
    static let runNotification = Notification.Name("com.normalcy.run")
    var statusItem: NSStatusItem?
    // Standard macOS settings window: tabs as toolbar icons, window resizes to each tab.
    lazy var settingsWindow: NSWindow = {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        let pages: [(String, String, AnyView, CGFloat)] = [
            ("General", "gearshape", AnyView(GeneralSettings()), 440),
            ("Commands", "command", AnyView(CommandSettings()), 680),
        ]
        for (title, icon, view, height) in pages {
            let vc = NSHostingController(rootView: view)
            vc.sizingOptions = []
            vc.preferredContentSize = NSSize(width: 560, height: height) // the window resizes to this per tab
            let item = NSTabViewItem(viewController: vc)
            item.label = title
            item.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        let w = NSWindow(contentViewController: tabs)
        w.toolbarStyle = .preference
        w.titleVisibility = .hidden // the selected tab already names the page
        w.styleMask.remove(.resizable)
        w.isReleasedWhenClosed = false
        return w
    }()

    func applicationDidFinishLaunching(_ n: Notification) {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        buildPanel()
        registerHotKey()
        // `Normalcy --run "t h"` from a script or terminal runs a command in this instance,
        // against the frontmost app, as if typed in the bar.
        DistributedNotificationCenter.default().addObserver(forName: Self.runNotification, object: nil, queue: .main) {
            [weak self] note in
            guard let text = note.object as? String, let self else { return }
            self.target = NSWorkspace.shared.frontmostApplication
            self.palette.submit(text)
        }
        buildStatusItem()
        CGRequestScreenCaptureAccess() // for desktop thumbnails
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Let the switch animation finish before capturing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.snapshotDesktop() }
        }
        snapshotDesktop()
    }

    func snapshotDesktop() {
        guard let id = Desktops.read().currentID else { return }
        Task { @MainActor in
            if let img = await Snapshot.capture() { palette.thumbs[id] = img }
        }
    }

    var wallpaperKey: String?
    func loadWallpaper() {
        let url = NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let key = "\(url?.path ?? "")|\(dark)" // reload when the wallpaper or appearance changes
        guard key != wallpaperKey else { return }
        wallpaperKey = key
        palette.wallpaper = url.flatMap { Wallpaper.load($0, dark: dark) }
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
        palette.submitContinuing = { [weak self] text in
            guard let self, let cmd = Command.parse(text, Store.shared.defs) else { return NSSound.beep() }
            // The bar stays up. Commands that activate an app take focus from it, so it
            // ignores losing focus until it takes it back once the command has landed.
            continuing = true
            palette.text = ""
            run(cmd)
            // shortcut: fixed delays, not completion callbacks; lengthen if focus comes back too early.
            let wait: Double = switch cmd {
            case .ctrlKey, .moveToDesktop: 0.7
            case .tabToWindow, .open: 0.6
            default: 0.2
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { self.refocus() }
        }
        palette.cancel = { [weak self] in self?.hide() }
        panel.contentView = NSHostingView(rootView: PaletteView(model: palette))
        preview.contentView = NSHostingView(rootView: LayoutPreview(model: palette))
        preview.isOpaque = false
        preview.backgroundColor = .clear
        preview.hasShadow = false
        preview.ignoresMouseEvents = true
        // Panels fade out by default. A fading bar gets caught in the desktop-switch animation
        // and reappears on the new desktop, so hide both instantly.
        panel.animationBehavior = .none
        preview.animationBehavior = .none
        preview.level = .floating
        preview.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // SwiftUI draws its own; the window shadow would outline the empty area
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
    }

    // The shortcut from Settings (Option+Space by default), re-registered whenever it changes.
    // Carbon hotkeys need no Accessibility permission.
    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ctx in
            Unmanaged<App>.fromOpaque(ctx!).takeUnretainedValue().show()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        let store = Store.shared
        store.$hotKey.combineLatest(store.$recordingHotKey).sink { [weak self] key, recording in
            guard let self else { return }
            if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
            if recording { return }
            let status = RegisterEventHotKey(key.keyCode, key.modifiers, EventHotKeyID(signature: OSType(0x4E524D4C), id: 1),
                                             GetApplicationEventTarget(), 0, &hotKey)
            store.hotKeyTaken = status != noErr
        }.store(in: &subs)
    }

    func show() {
        target = NSWorkspace.shared.frontmostApplication
        palette.text = ""
        palette.desktops = Desktops.read()
        loadWallpaper()
        snapshotDesktop()
        // A screen-tall column; the view places its content inside by style and position.
        if let v = NSScreen.main?.visibleFrame {
            panel.setFrame(NSRect(x: v.midX - 300, y: v.minY, width: 600, height: v.height), display: false)
            preview.setFrame(v, display: false) // same area window commands fill
        }
        preview.orderFront(nil) // first, so the bar stays above it
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            self.palette.focusToken += 1
            withAnimation(.uiEaseOut(0.15)) { self.palette.visible = true }
        }
    }

    // Closing stays instant: a fading bar would get caught in a desktop switch.
    func hide() {
        panel.orderOut(nil)
        preview.orderOut(nil)
        palette.visible = false
    }

    var continuing = false // Shift+Enter ran a command; keep the bar while it runs
    func windowDidResignKey(_ n: Notification) { if !continuing { hide() } }

    // Back to typing after a Shift+Enter command, against whatever app is now in front.
    func refocus() {
        continuing = false
        guard panel.isVisible else { return }
        target = NSWorkspace.shared.frontmostApplication
        palette.desktops = Desktops.read()
        panel.makeKeyAndOrderFront(nil)
        palette.focusToken += 1
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
            // Let the window server drop the hidden bar before the desktop slides.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.desktopKeys(key).forEach { self.pressCtrl($0) }
            }
        case .moveToDesktop(let key):
            moveWindow(toDesktop: key)
        case .layout(let f):
            place(f)
        case .tabToWindow(let layout):
            // The bar took key focus from the app's window. Hand it back first, or Safari
            // applies the command to a different tab than the one showing.
            target?.activate()
            let origin = focusedWindow()
            if let origin { AXUIElementPerformAction(origin, kAXRaiseAction as CFString) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let before = self.windows()
                guard self.pressMenuItem("Move Tab to New Window") else { return NSSound.beep() }
                guard let origin else { return }
                self.waitForNewWindow(before: before) { new in
                    // No new window: no tab moved out (e.g. only one tab), so leave things alone.
                    guard let new else { return }
                    // Safari opens the moved tab as the new window. Apps using standard macOS tabs
                    // keep the moved tab's own window, and the tabs left behind become the new one.
                    let movedIsNew = self.focusedWindow().map { CFEqual($0, new) } ?? false
                    if let layout { self.place(layout, window: movedIsNew ? new : origin) }
                }
            }
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

    // Ctrl+N only works when "Switch to Desktop N" is turned on (off by default).
    // When it's off, step there with Ctrl+Left/Right from the current desktop instead.
    func desktopKeys(_ key: CGKeyCode) -> [CGKeyCode] {
        guard let i = Command.digitKeys.firstIndex(of: key), !Self.shortcutEnabled(118 + i),
              let cur = Desktops.read().current else { return [key] }
        let n = i + 1
        return Array(repeating: n > cur ? 124 : 123, count: abs(n - cur))
    }

    // Mission Control shortcut IDs: 118 = Switch to Desktop 1, 119 = Desktop 2, ...
    static func shortcutEnabled(_ id: Int) -> Bool {
        let all = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        return (all?["\(id)"] as? [String: Any])?["enabled"] as? Bool ?? false
    }

    // No public API moves a window between spaces. Instead: hold the mouse down on the
    // title bar, switch desktop, release — macOS carries a dragged window along.
    func moveWindow(toDesktop key: CGKeyCode) {
        let keys = desktopKeys(key)
        guard AXIsProcessTrusted(), !keys.isEmpty, let w = focusedWindow(), let grab = titleBarPoint(w) else {
            NSSound.beep(); return
        }
        let restore = CGEvent(source: nil)?.location ?? grab
        postMouse(.mouseMoved, grab)
        postMouse(.leftMouseDown, grab)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            keys.forEach { self.pressCtrl($0) }
            // Wait for the space-switch animation(s) before letting go.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + 0.3 * Double(keys.count - 1)) {
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

    // Apps with native macOS tabs (Ghostty, Safari, Finder, Terminal...) list this under the Window menu.
    // Pressing it through Accessibility works no matter which menu or shortcut the app uses.
    func pressMenuItem(_ title: String) -> Bool {
        guard let pid = target?.processIdentifier else { return false }
        // Menu bar > menu bar item > menu > menu item: 3 levels down.
        func find(_ e: AXUIElement, _ depth: Int) -> AXUIElement? {
            if (axAttr(e, kAXTitleAttribute) as String?) == title { return e }
            guard depth < 3, let kids: [AXUIElement] = axAttr(e, kAXChildrenAttribute) else { return nil }
            return kids.lazy.compactMap { find($0, depth + 1) }.first
        }
        guard let bar: AXUIElement = axAttr(AXUIElementCreateApplication(pid), kAXMenuBarAttribute),
              let item = find(bar, 0) else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    func windows() -> [AXUIElement] {
        guard let app = target else { return [] }
        return axAttr(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) ?? []
    }

    // Polls up to 1 s for a window that wasn't there before; how long it takes varies by app.
    func waitForNewWindow(before: [AXUIElement], tries: Int = 20, then: @escaping (AXUIElement?) -> Void) {
        if let w = windows().first(where: { w in !before.contains { CFEqual($0, w) } }) { return then(w) }
        guard tries > 0 else { return then(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.waitForNewWindow(before: before, tries: tries - 1, then: then)
        }
    }

    func focusedWindow() -> AXUIElement? {
        guard let app = target else { return nil }
        var win: CFTypeRef?
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        guard AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &win) == .success,
              let win else { return nil }
        return (win as! AXUIElement)
    }

    func place(_ f: CGRect, window: AXUIElement? = nil) {
        // shortcut: uses the screen with the panel, not the window's own screen; fix for multi-monitor
        guard let w = window ?? focusedWindow(), let screen = NSScreen.main, let primary = NSScreen.screens.first else { return }
        let v = screen.visibleFrame
        // AX uses top-left origin of the primary screen; AppKit uses bottom-left.
        let bounds = CGRect(x: v.minX, y: primary.frame.maxY - v.maxY, width: v.width, height: v.height)
        let target = CGRect(x: bounds.minX + v.width * f.minX, y: bounds.minY + v.height * f.minY,
                            width: v.width * f.width, height: v.height * f.height)
        var origin = target.origin, size = target.size
        AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin)!)
        AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
        // Fixed-size windows (like many settings windows) ignore the size: center what they kept.
        guard let actual = axFrame(w)?.size, actual != target.size else { return }
        var centered = Self.center(actual, in: target, bounds: bounds)
        AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &centered)!)
    }

    // Origin that centers a window of this size in the target, kept on screen when it's bigger.
    static func center(_ size: CGSize, in target: CGRect, bounds: CGRect) -> CGPoint {
        CGPoint(x: max(bounds.minX, min(target.midX - size.width / 2, bounds.maxX - size.width)),
                y: max(bounds.minY, min(target.midY - size.height / 2, bounds.maxY - size.height)))
    }
}

func axAttr<T>(_ e: AXUIElement, _ name: String) -> T? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success else { return nil }
    return v as? T
}

@main
enum Main {
    static let app = App()

    static func main() {
        if CommandLine.arguments.contains("--selftest") { selfTest(); return }
        if CommandLine.arguments.contains("--desktops") { print(Desktops.read()); return }
        if let i = CommandLine.arguments.firstIndex(of: "--run"), i + 1 < CommandLine.arguments.count {
            DistributedNotificationCenter.default().postNotificationName(
                App.runNotification, object: CommandLine.arguments[i + 1], deliverImmediately: true)
            return
        }
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
        precondition(Command.parse("t", d) == .tabToWindow(nil))
        precondition(Command.parse("t h", d) == .tabToWindow(CGRect(x: 0, y: 0, width: 0.5, height: 1)))
        precondition(Command.parse("t f", d) == .tabToWindow(CGRect(x: 0, y: 0, width: 1, height: 1)))
        precondition(Command.parse("t x", d) == nil)
        precondition(Command.parse("t o", d) == nil) // only layout triggers allowed
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
        var continued: String?
        p.submitContinuing = { continued = $0 }
        p.text = "h"
        p.enter(continuing: true)
        precondition(continued == "h")

        // Desktops: full-screen spaces (type 4) aren't numbered.
        let fake: [[String: Any]] = [[
            "Current Space": ["ManagedSpaceID": 7],
            "Spaces": [["ManagedSpaceID": 3, "type": 0], ["ManagedSpaceID": 9, "type": 4], ["ManagedSpaceID": 7, "type": 0]],
        ]]
        precondition(Desktops.parse(fake) == Desktops(ids: [3, 7], currentID: 7) && Desktops.parse(fake).current == 2)
        precondition(Desktops.parse([]) == Desktops())
        p.desktops = Desktops(ids: [10, 20, 30, 40], currentID: 20)
        p.text = "d"
        precondition(p.desktopCommand?.id == "desktop" && p.desktopTarget == nil)
        p.text = "m h"
        precondition(p.desktopCommand?.id == "move" && p.desktopTarget == 1)
        p.text = "d 4"
        precondition(p.desktopTarget == 4)
        p.text = "f"
        precondition(p.desktopCommand == nil)
        // Minimal style key-cap blocks.
        precondition(Palette.keyBlocks("", showSpaces: false) == [""]) // empty block on open
        precondition(Palette.keyBlocks("o Safari", showSpaces: false) == ["o", "Safari"])
        precondition(Palette.keyBlocks("o Safari", showSpaces: true) == ["o", "␣", "Safari"])
        precondition(Palette.keyBlocks("o ", showSpaces: false) == ["o", ""]) // space pops a new block
        precondition(Palette.keyBlocks("   ", showSpaces: false) == [""])
        precondition(Palette.keyBlocks("d ", showSpaces: true) == ["d", "␣", ""])
        precondition(Palette.keyBlocks("←↓", showSpaces: false) == ["←↓"])
        precondition(Palette.spacedArrows("←↓") == "←\u{2009}↓")
        precondition(Palette.spacedArrows("set") == "set")
        // Arrow keys type h j k l, adding the space after a command that takes a direction.
        let r = Palette()
        r.defs = { d }
        r.typeArrow("←")
        precondition(r.text == "←" && r.matches.first?.id == "left")
        precondition(Command.parse("←", d) == .layout(CGRect(x: 0, y: 0, width: 0.5, height: 1)))
        precondition(Command.parse("↓", d) == .layout(CGRect(x: 0, y: 0.5, width: 1, height: 0.5)))
        r.text = "t"
        r.typeArrow("←")
        precondition(r.text == "t ←")
        precondition(Command.parse("t ←", d) == .tabToWindow(CGRect(x: 0, y: 0, width: 0.5, height: 1)))
        r.text = "d "
        r.typeArrow("→")
        precondition(r.text == "d →" && Command.parse("d →", d) == .ctrlKey(124))
        precondition(Command.parse("d ↑", d) == nil) // desktops only go left/right
        var renamed = d
        renamed[renamed.firstIndex { $0.id == "left" }!].trigger = "a"
        precondition(Command.parse("←", renamed) == .layout(CGRect(x: 0, y: 0, width: 0.5, height: 1)))

        // Layout preview follows the typed or highlighted window command.
        let q = Palette()
        q.defs = { d }
        q.text = "h"
        precondition(q.layoutPreview == CGRect(x: 0, y: 0, width: 0.5, height: 1))
        q.text = "t l"
        precondition(q.layoutPreview == CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        q.text = "o Safari"
        precondition(q.layoutPreview == nil)
        q.text = "ha" // no exact match; selected row "Left Half" (title match) still previews
        precondition(q.layoutPreview == CGRect(x: 0, y: 0, width: 0.5, height: 1))
        // Thirds and quarters, by trigger, by arrows, and after t.
        // Checked against plain numbers: CGRect also takes Ints, where 1 / 3 is 0.
        precondition(Command.layoutRect(.leftThird)!.width > 0.33 && Command.layoutRect(.leftThird)!.width < 0.34)
        precondition(Command.layoutRect(.rightThird)!.minX > 0.66)
        precondition(Command.parse("h3", d) == .layout(CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1)))
        precondition(Command.parse("l3", d) == .layout(CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)))
        precondition(Command.parse("hk", d) == .layout(CGRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        precondition(Command.parse("lj", d) == .layout(CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)))
        precondition(Command.parse("←↑", d) == Command.parse("hk", d))
        precondition(Command.parse("↑←", d) == Command.parse("hk", d))
        precondition(Command.parse("→↓", d) == Command.parse("lj", d))
        precondition(Command.parse("←←", d) == nil)
        precondition(Command.parse("kh", d) == Command.parse("hk", d))
        precondition(Command.parse("jl", d) == Command.parse("lj", d))
        precondition(Command.parse("h↑", d) == Command.parse("hk", d))
        precondition(Command.parse("hl", d) == nil) // left + right is no corner
        precondition(Command.parse("←3", d) == Command.parse("h3", d))
        precondition(Command.parse("→3", d) == Command.parse("l3", d))
        precondition(Command.parse("t ←3", d) == .tabToWindow(Command.layoutRect(.leftThird)))
        precondition(Command.parse("t kh", d) == .tabToWindow(CGRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        precondition(Command.parse("t c3", d) == .tabToWindow(CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1)))
        let t = Palette()
        t.defs = { d }
        t.text = "h"
        precondition(t.matches.first?.id == "left") // "h" alone still means left half
        t.typeArrow("←")
        t.text = "←"
        t.typeArrow("↑")
        precondition(t.text == "←↑" && t.layoutPreview == CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        t.text = "kh"
        precondition(t.matches.first?.id == "topLeft")
        // Direction keys: changing them renames every trigger built from them, all at once.
        let ijkl = CommandDef.setDirections(Array("jkil").map(String.init), in: d)
        func trig(_ a: Action, _ defs: [CommandDef]) -> String { defs.first { $0.id == a.rawValue }!.trigger }
        precondition(trig(.left, ijkl) == "j" && trig(.bottom, ijkl) == "k" && trig(.top, ijkl) == "i")
        precondition(trig(.leftThird, ijkl) == "j3" && trig(.bottomLeft, ijkl) == "jk" && trig(.topRight, ijkl) == "li")
        precondition(trig(.centerThird, ijkl) == "c3")
        precondition(Command.parse("d j", ijkl) == .ctrlKey(123) && Command.parse("d h", ijkl) == nil)
        precondition(Command.parse("ij", ijkl) == Command.parse("hk", d))
        precondition(Command.spell("<left> <right>", ijkl) == "j l")
        var off = d
        off[off.firstIndex { $0.id == "left" }!].enabled = false
        precondition(Command.parse("d h", off) == .ctrlKey(123)) // direction key works with Left Half off
        // The empty key cap names the argument once a command and a space are typed.
        let h = Palette()
        h.defs = { d }
        h.text = "o "
        precondition(h.argPlaceholder == "app")
        h.text = "d"
        precondition(h.argPlaceholder == nil)
        h.text = "t  "
        precondition(h.argPlaceholder == "position")
        h.text = "d 2"
        precondition(h.argPlaceholder == nil)
        h.text = "h "
        precondition(h.argPlaceholder == nil)
        // Recorded shortcuts need Control, Option or Command, and read like the menu bar.
        func keyEvent(_ f: NSEvent.ModifierFlags, _ chars: String, _ code: Int) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: f, timestamp: 0, windowNumber: 0,
                             context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false,
                             keyCode: UInt16(code))!
        }
        precondition(HotKey(event: keyEvent([.option], " ", kVK_Space)) == .standard)
        precondition(HotKey(event: keyEvent([.command, .shift], "k", kVK_ANSI_K))?.label == "⇧⌘ K")
        precondition(HotKey(event: keyEvent([.shift], "k", kVK_ANSI_K)) == nil)
        // A window that kept its size is centered in the target area, and stays on screen.
        let screen = CGRect(x: 0, y: 25, width: 1000, height: 800)
        precondition(App.center(CGSize(width: 400, height: 300), in: screen, bounds: screen) == CGPoint(x: 300, y: 275))
        precondition(App.center(CGSize(width: 400, height: 300), in: CGRect(x: 0, y: 25, width: 500, height: 800), bounds: screen) == CGPoint(x: 50, y: 275))
        precondition(App.center(CGSize(width: 600, height: 900), in: CGRect(x: 500, y: 25, width: 500, height: 800), bounds: screen) == CGPoint(x: 400, y: 25))
        // Every default trigger is unique.
        precondition(Set(d.map(\.trigger)).count == d.count)
        print("selftest ok")
    }
}
