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
//   + -            window: 10% bigger / smaller, staying centered
//   re <h|l|k|j>…  window: narrower / wider / shorter / taller, one step per key
//   s <j|k|h|l>…   scroll the window down / up / left / right as each key is pressed
//   set            open settings
enum Command: Equatable {
    case open(String)
    case focus(String)
    case focusWindow(Action) // the nearest window on this desktop to the left / right / top / bottom
    case ctrlKey(CGKeyCode)
    case moveToDesktop(CGKeyCode)
    case tabToWindow(CGRect?) // optional layout for the new window
    case layout(CGRect) // fractions of the screen, top-left origin
    case resize(Int) // steps bigger (or smaller, if negative) around the window's center
    case resizeEdge(CGSize) // steps to move the right and bottom edges out (or in, if negative)
    case scroll(CGSize) // steps right and down (negative: left and up)
    case pointerTo(CGPoint) // global coordinates, top-left origin
    case pointerBy(CGSize) // points right and down
    case click(right: Bool, count: Int)
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
        case .focus:
            if let d = direction(arg, in: defs) { return .focusWindow(d) }
            return arg.isEmpty ? nil : .focus(arg)
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
        case .grow: return .resize(1)
        case .shrink: return .resize(-1)
        case .resize: return directionSteps(arg, defs).map { .resizeEdge($0) }
        case .scroll: return directionSteps(arg, defs).map { .scroll($0) }
        case .pointer, .pointerStep:
            // The pointer moves as keys are pressed; Return clicks: "mo" left, "mo r" right, "mo 2" double.
            switch arg {
            case "": return .click(right: false, count: 1)
            case "r": return .click(right: true, count: 1)
            case "2": return .click(right: false, count: 2)
            default: return nil
            }
        case .settings: return .settings
        }
    }

    // Each direction key is one step, summed: "ll" = two right, "lj" = one right and one down.
    // nil if empty or anything but a direction is typed.
    static func directionSteps(_ arg: String, _ defs: [CommandDef]) -> CGSize? {
        let steps: [Action: CGSize] = [.right: CGSize(width: 1, height: 0), .left: CGSize(width: -1, height: 0),
                                       .bottom: CGSize(width: 0, height: 1), .top: CGSize(width: 0, height: -1)]
        let moves = arg.map { direction(String($0), in: defs).flatMap { steps[$0] } }
        guard !moves.isEmpty, !moves.contains(nil) else { return nil }
        return moves.compactMap { $0 }.reduce(.zero) { CGSize(width: $0.width + $1.width, height: $0.height + $1.height) }
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
            ("General", "gearshape", AnyView(GeneralSettings()), 460),
            ("Commands", "command", AnyView(CommandSettings()), 680),
            ("Windows", "macwindow", AnyView(WindowSettings()), 680),
            ("Keys", "keyboard", AnyView(KeySettings()), 450),
        ]
        for (title, icon, view, height) in pages {
            let vc = NSHostingController(rootView: view)
            vc.sizingOptions = []
            vc.preferredContentSize = NSSize(width: 560, height: height) // the window resizes to this per tab
            vc.title = title // shown as the window title, like Safari's Settings
            let item = NSTabViewItem(viewController: vc)
            item.label = title
            item.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        let w = NSWindow(contentViewController: tabs)
        w.toolbarStyle = .preference
        // A plain bar in the window's color: the default one shows the page scrolling behind it.
        w.titlebarAppearsTransparent = true
        // That drops the line under the tabs; draw it back.
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        tabs.view.addSubview(line)
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: tabs.view.safeAreaLayoutGuide.topAnchor),
            line.leadingAnchor.constraint(equalTo: tabs.view.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: tabs.view.trailingAnchor),
        ])
        w.styleMask.remove(.resizable)
        w.isReleasedWhenClosed = false
        return w
    }()

    func applicationDidFinishLaunching(_ n: Notification) {
        // The icon macOS shows for Normalcy, e.g. in alerts and app switchers.
        NSApp.applicationIconImage = Bundle.module.url(forResource: "AppIcon", withExtension: "png").flatMap(NSImage.init(contentsOf:))
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        buildPanel()
        registerHotKey()
        trackRecentApps()
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
            // Shift+Enter desktop switch: take focus back after the new desktop's app has taken it,
            // or the bar loses focus right after and hides. Each further switch pushes this back.
            if self?.continuing == true { self?.scheduleRefocus(after: 0.3) }
        }
        snapshotDesktop()
    }

    var thumbWindows: [Int: Set<CGWindowID>] = [:] // space ID -> windows its thumbnail shows
    // Windows last seen actually showing. Apps keep closed windows around, and from another desktop
    // they can't be told from open ones, so only windows seen on screen get drawn into thumbnails.
    var seen = Set<CGWindowID>()

    // The current desktop is captured as it looks. Others can't be, so any whose windows changed
    // since their thumbnail (or that have none yet) get one rebuilt from their windows.
    func snapshotDesktop() {
        let desks = Desktops.read()
        let settings = settingsWindow.isVisible ? [CGWindowID(settingsWindow.windowNumber)] : []
        let all = Snapshot.windowsBySpace(also: Set(settings))
        for w in desks.currentID.flatMap({ all[$0] }) ?? [] {
            if w.onScreen { seen.insert(w.id) } else { seen.remove(w.id) }
        }
        let windows = all.mapValues { $0.filter { seen.contains($0.id) } }
        Task { @MainActor in
            if let id = desks.currentID, let img = await Snapshot.capture(excluding: [panel, preview]) {
                palette.thumbs[id] = img
                // Wallpaper as it really renders; the file on disk isn't always readable.
                if let bare = await Snapshot.capture(excluding: [panel, preview], bare: true) { palette.wallpaper = bare }
                thumbWindows[id] = Set(windows[id, default: []].map(\.id))
            }
            for id in desks.ids where id != desks.currentID {
                let ws = windows[id, default: []], ids = Set(ws.map(\.id))
                guard thumbWindows[id] != ids, let img = await Snapshot.compose(ws, wallpaper: palette.wallpaper) else { continue }
                palette.thumbs[id] = img
                thumbWindows[id] = ids
            }
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
            // Scrolling and pointing go in small steps, so keep "s " / "mo " ready; the rest starts blank.
            let stepping = switch cmd { case .scroll, .click: true; default: false }
            let again = stepping ? (text.split(separator: " ").first.map(String.init) ?? "") + " " : ""
            // The bar stays up. Commands that activate an app take focus from it, so it
            // ignores losing focus until it takes it back once the command has landed.
            continuing = true
            palette.text = again
            run(cmd)
            // shortcut: fixed delays, not completion callbacks; lengthen if focus comes back too early.
            // Desktop switches come back once the switch lands (see the space-change observer);
            // their delay is only the fallback for when no switch happens, like "d l" on the last desktop.
            let wait: Double = switch cmd {
            case .ctrlKey, .moveToDesktop: 1.5
            case .tabToWindow, .open: 0.6
            default: 0.2
            }
            scheduleRefocus(after: wait)
        }
        palette.cancel = { [weak self] in self?.hide() }
        palette.live = { [weak self] in self?.run($0) }
        palette.loadPreview = { [weak self] pid in
            Task { @MainActor in
                if let img = await Snapshot.appWindow(pid) { self?.palette.appPreviews[pid] = img }
            }
        }
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
        captureWindow()
        palette.apps = runningApps()
        palette.installed = Self.installedApps()
        palette.text = ""
        palette.desktops = Desktops.read()
        loadWallpaper()
        snapshotDesktop()
        // A screen-tall column; the view places its content inside by style and position.
        if let v = NSScreen.main?.visibleFrame {
            panel.setFrame(NSRect(x: v.midX - 300, y: v.minY, width: 600, height: v.height), display: false)
            preview.setFrame(v, display: false) // same area window commands fill
        }
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            // A pass later, so it has redrawn without the last command's box; below the bar.
            self.preview.order(.below, relativeTo: self.panel.windowNumber)
            self.palette.focusToken += 1
            withAnimation(.uiEaseOut(0.15)) { self.palette.visible = true }
        }
    }

    // Closing stays instant: a fading bar would get caught in a desktop switch.
    func hide() {
        panel.orderOut(nil)
        preview.orderOut(nil)
        // Drop the last command's preview box now, unanimated, so it never shows on the next open.
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { palette.text = "" }
        palette.visible = false
    }

    var continuing = false // Shift+Enter ran a command; keep the bar while it runs
    func windowDidResignKey(_ n: Notification) { if !continuing { hide() } }

    // Back to typing after a Shift+Enter command, against whatever app is now in front.
    // .app bundles in the Applications folders and one folder down (Utilities and the like).
    static func installedApps() -> [AppItem] {
        let fm = FileManager.default
        let roots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        var paths: [String] = []
        for root in roots {
            for entry in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where !entry.hasPrefix(".") {
                let path = root + "/" + entry
                if entry.hasSuffix(".app") { paths.append(path); continue }
                for sub in (try? fm.contentsOfDirectory(atPath: path)) ?? [] where sub.hasSuffix(".app") {
                    paths.append(path + "/" + sub)
                }
            }
        }
        var seen = Set<String>()
        return paths
            .map { AppItem(name: fm.displayName(atPath: $0).replacingOccurrences(of: ".app", with: ""), path: $0) }
            .filter { seen.insert($0.name).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // The apps Cmd+Tab shows: ones with a window showing on this desktop, plus Finder, most
    // recently used first, then the rest by name.
    func runningApps() -> [AppItem] {
        let rank = { (pid: pid_t) in self.recentApps.firstIndex(of: pid) ?? Int.max }
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let withWindow = Set(info.compactMap { w -> pid_t? in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let f = CGRect(dictionaryRepresentation: b), f.width > 50, f.height > 50 else { return nil }
            return w[kCGWindowOwnerPID as String] as? pid_t
        })
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0 != NSRunningApplication.current }
            .filter { withWindow.contains($0.processIdentifier) || $0.bundleIdentifier == "com.apple.finder" }
            .map { AppItem(name: $0.localizedName ?? "", icon: $0.icon, pid: $0.processIdentifier) }
            .sorted { (rank($0.pid), $0.name.lowercased()) < (rank($1.pid), $1.name.lowercased()) }
    }

    var recentApps: [pid_t] = [] // pids by last activation, newest first, since Normalcy started
    func trackRecentApps() {
        if let front = NSWorkspace.shared.frontmostApplication { recentApps = [front.processIdentifier] }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            recentApps.removeAll { $0 == app.processIdentifier }
            recentApps.insert(app.processIdentifier, at: 0)
        }
    }

    // The target window's frame, so resize commands can preview where it will go.
    func captureWindow() {
        palette.window = focusedWindow().flatMap(axFrame)
        palette.screen = Self.screenBounds()
    }

    var pendingRefocus: DispatchWorkItem?
    func scheduleRefocus(after delay: Double) {
        pendingRefocus?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.refocus() }
        pendingRefocus = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    func refocus() {
        continuing = false
        guard panel.isVisible else { return }
        target = NSWorkspace.shared.frontmostApplication
        captureWindow()
        palette.apps = runningApps()
        palette.desktops = Desktops.read()
        snapshotDesktop() // the command may have changed this desktop
        panel.makeKeyAndOrderFront(nil)
        palette.focusToken += 1
    }

    func run(_ cmd: Command) {
        switch cmd {
        case .open(let name):
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-a", name])
        case .focus(let q):
            // An exact name wins, so picking "Safari" from the list never lands on "Safari Technology Preview".
            let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            let name = { (a: NSRunningApplication) in (a.localizedName ?? "").lowercased() }
            (apps.first { name($0) == q.lowercased() } ?? apps.first { name($0).hasPrefix(q.lowercased()) })?.activate()
        case .focusWindow(let dir):
            focusWindow(dir)
        case .ctrlKey(let key):
            // Let the window server drop the hidden bar before the desktop slides.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.desktopKeys(key).forEach { self.pressCtrl($0) }
            }
        case .moveToDesktop(let key):
            moveWindow(toDesktop: key)
        case .layout(let f):
            place(f)
        case .resize, .resizeEdge:
            resizeFocused(cmd)
        case .scroll(let steps):
            scroll(steps)
        case .pointerTo(let p):
            postMouse(.mouseMoved, p)
        case .pointerBy(let d):
            let p = CGEvent(source: nil)?.location ?? .zero
            postMouse(.mouseMoved, CGPoint(x: p.x + d.width, y: p.y + d.height))
        case .click(let right, let count):
            click(right: right, count: count)
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

    // Clicks where the pointer is. The bar may be under it (Shift+Return keeps it up), so clicks
    // pass through it for a moment.
    func click(right: Bool, count: Int) {
        panel.ignoresMouseEvents = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let p = CGEvent(source: nil)?.location ?? .zero
            let (down, up, button): (CGEventType, CGEventType, CGMouseButton) =
                right ? (.rightMouseDown, .rightMouseUp, .right) : (.leftMouseDown, .leftMouseUp, .left)
            for n in 1...count {
                for type in [down, up] {
                    let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button)
                    e?.setIntegerValueField(.mouseEventClickState, value: Int64(n)) // 2 makes it a double-click
                    e?.post(tap: .cghidEventTap)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.panel.ignoresMouseEvents = false }
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

    // Windows of regular apps showing on this desktop, front to back. Frames are global, top-left origin.
    static func visibleWindows() -> [(pid: pid_t, frame: CGRect)] {
        let regular = Set(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0 != NSRunningApplication.current }.map(\.processIdentifier))
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, regular.contains(pid),
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let f = CGRect(dictionaryRepresentation: b), f.width > 50, f.height > 50 else { return nil }
            return (pid, f)
        }
    }

    // The app's AX window with exactly this frame.
    func axWindow(_ pid: pid_t, _ frame: CGRect) -> AXUIElement? {
        let ax: [AXUIElement] = axAttr(AXUIElementCreateApplication(pid), kAXWindowsAttribute) ?? []
        return ax.first { axFrame($0) == frame }
    }

    // Switches to the nearest window on this desktop in that direction from the front window.
    func focusWindow(_ dir: Action) {
        let wins = Self.visibleWindows()
        // The list is front to back, so the target app's first window is the one in front.
        guard let cur = wins.firstIndex(where: { $0.pid == target?.processIdentifier }),
              let i = Self.neighbor(of: wins[cur].frame, in: wins.map(\.frame), toward: dir, skip: cur),
              let app = NSRunningApplication(processIdentifier: wins[i].pid) else { return NSSound.beep() }
        if let w = axWindow(wins[i].pid, wins[i].frame) {
            AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
        }
        app.activate()
    }

    // Index of the closest frame whose center lies that way from `cur`'s center; sideways
    // distance counts double so the window straight ahead wins over one off to the side.
    static func neighbor(of cur: CGRect, in frames: [CGRect], toward dir: Action, skip: Int) -> Int? {
        let score = { (f: CGRect) -> CGFloat? in
            let dx = f.midX - cur.midX, dy = f.midY - cur.midY
            let (ahead, side): (CGFloat, CGFloat) = switch dir {
            case .left: (-dx, dy)
            case .right: (dx, dy)
            case .top: (-dy, dx)
            default: (dy, dx)
            }
            return ahead > 0 ? ahead + 2 * abs(side) : nil
        }
        return frames.indices.filter { $0 != skip && frames[$0] != cur }
            .compactMap { i in score(frames[i]).map { (i, $0) } }
            .min { $0.1 < $1.1 }?.0
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
        setFrame(w, target, bounds: bounds)
    }

    // Scrolls the target window a quarter of its height (or width) per step, aimed at the
    // window's center; the pointer doesn't move. Apps ignore scrolls posted to them directly,
    // so it goes through the system, and the bar lets it pass in case it sits over that spot.
    // The distance is spread over a few frames, easing out, so it glides instead of jumping;
    // steps pressed while it's still moving add to what's left.
    var scrollLeft = CGSize.zero // pixels still to scroll: positive is up / left, as wheel values
    var scrollAt = CGPoint.zero
    var scrollTimer: Timer?

    func scroll(_ steps: CGSize) {
        guard let w = focusedWindow(), let f = axFrame(w) else { return }
        scrollLeft.width -= steps.width * f.width / 4
        scrollLeft.height -= steps.height * f.height / 4
        scrollAt = CGPoint(x: f.midX, y: f.midY)
        guard scrollTimer == nil else { return }
        panel.ignoresMouseEvents = true
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            guard let self else { return t.invalidate() }
            // A quarter of what's left each frame: fast at first, settling in about a quarter second.
            let dx = Self.scrollPart(scrollLeft.width), dy = Self.scrollPart(scrollLeft.height)
            if dx == 0 && dy == 0 {
                t.invalidate()
                scrollTimer = nil
                scrollLeft = .zero
                panel.ignoresMouseEvents = false
                return
            }
            scrollLeft.width -= CGFloat(dx)
            scrollLeft.height -= CGFloat(dy)
            let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
            e?.location = scrollAt
            e?.post(tap: .cghidEventTap)
        }
    }

    // Whole pixels to scroll this frame: a quarter of what's left, at least 1, 0 when done.
    static func scrollPart(_ left: CGFloat) -> Int32 {
        guard abs(left) >= 1 else { return 0 }
        let part = (left / 4).rounded()
        return Int32(part == 0 ? (left > 0 ? 1 : -1) : part)
    }

    // Visible area of the bar's screen, in AX coordinates (top-left origin of the primary screen).
    static func screenBounds() -> CGRect? {
        guard let v = NSScreen.main?.visibleFrame, let primary = NSScreen.screens.first else { return nil }
        return CGRect(x: v.minX, y: primary.frame.maxY - v.maxY, width: v.width, height: v.height)
    }

    func resizeFocused(_ cmd: Command) {
        guard let w = focusedWindow(), let frame = axFrame(w), let bounds = Self.screenBounds(),
              let target = Self.resized(frame, cmd, bounds: bounds, steps: Store.shared.resizeSteps) else { return }
        // Read the neighbors before the window moves, while their frames still line up.
        let others = Store.shared.resizeNeighbors ? Self.visibleWindows().filter { $0.frame != frame } : []
        setFrame(w, target, bounds: bounds)
        guard let now = axFrame(w) else { return }
        for (i, f) in Self.neighborsResized(old: frame, new: now, others: others.map(\.frame)) {
            if let n = axWindow(others[i].pid, others[i].frame) { setFrame(n, f, bounds: bounds) }
        }
    }

    // Windows beside an edge that moved follow it, keeping their gap: growing the left window
    // of a side-by-side pair shrinks the right one. Returns new frames by index into `others`.
    // A window counts as beside an edge when it's within 20 points and overlaps along it.
    static func neighborsResized(old: CGRect, new: CGRect, others: [CGRect]) -> [Int: CGRect] {
        let tol: CGFloat = 20
        var out: [Int: CGRect] = [:]
        for (i, o) in others.enumerated() {
            var minX = o.minX, maxX = o.maxX, minY = o.minY, maxY = o.maxY
            if o.maxY > old.minY + tol, o.minY < old.maxY - tol { // side by side
                if abs(o.minX - old.maxX) < tol { minX += new.maxX - old.maxX }
                if abs(o.maxX - old.minX) < tol { maxX += new.minX - old.minX }
            }
            if o.maxX > old.minX + tol, o.minX < old.maxX - tol { // stacked
                if abs(o.minY - old.maxY) < tol { minY += new.maxY - old.maxY }
                if abs(o.maxY - old.minY) < tol { maxY += new.minY - old.minY }
            }
            let f = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            if f != o, f.width >= 100, f.height >= 100 { out[i] = f }
        }
        return out
    }

    // Where a resize command puts a window, kept within the screen. Steps are from Settings:
    // .resize scales the window by `steps.scale` per step around its center; .resizeEdge moves an
    // edge by `steps.edge` of the screen per step, the way typed: the right and bottom edges, or the
    // left / top edge of a window against the right / bottom of the screen, like dragging the line
    // between two windows.
    static func resized(_ frame: CGRect, _ cmd: Command, bounds: CGRect, steps: ResizeSteps) -> CGRect? {
        switch cmd {
        case .resize(let n):
            let scale = pow(1 + steps.scale, CGFloat(n))
            let size = CGSize(width: min(frame.width * scale, bounds.width), height: min(frame.height * scale, bounds.height))
            return CGRect(origin: center(size, in: frame, bounds: bounds), size: size)
        case .resizeEdge(let d):
            // One axis: new (start, end) of the window between the screen's bStart and bEnd.
            func edges(_ start: CGFloat, _ end: CGFloat, _ bStart: CGFloat, _ bEnd: CGFloat, _ by: CGFloat) -> (CGFloat, CGFloat) {
                let tol: CGFloat = 20, atStart = start < bStart + tol, atEnd = end > bEnd - tol
                // Against both sides: pull in the edge on the side typed away from ("re l" on a full
                // window frees its left edge), so it shrinks toward the other side.
                if atStart, atEnd, by > 0 { return (min(start + by, end - 100), end) }
                if atStart, atEnd, by < 0 { return (start, max(end + by, start + 100)) }
                // Against the far side only: the near edge is the free one, so it moves.
                if atEnd, !atStart { return (min(max(start + by, bStart), end - 100), end) }
                let size = min(max(end - start + by, 100), bEnd - bStart)
                let s = min(start, bEnd - size)
                return (s, s + size)
            }
            let x = edges(frame.minX, frame.maxX, bounds.minX, bounds.maxX, d.width * steps.edge * bounds.width)
            let y = edges(frame.minY, frame.maxY, bounds.minY, bounds.maxY, d.height * steps.edge * bounds.height)
            return CGRect(x: x.0, y: y.0, width: x.1 - x.0, height: y.1 - y.0)
        default: return nil
        }
    }

    // Target rect in AX coordinates (top-left origin of the primary screen).
    func setFrame(_ w: AXUIElement, _ target: CGRect, bounds: CGRect) {
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
        if CommandLine.arguments.contains("--desktops") { print(Desktops.read(), Snapshot.windowsBySpace().mapValues(\.count)); return }
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
        precondition(Command.parse("b h", d) == .focusWindow(.left))
        precondition(Command.parse("b ho", d) == .focus("ho"))
        let tiles = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 200, y: 0, width: 100, height: 100),
                     CGRect(x: 200, y: 200, width: 100, height: 100), CGRect(x: 400, y: 150, width: 100, height: 100)]
        precondition(App.neighbor(of: tiles[0], in: tiles, toward: .right, skip: 0) == 1)
        precondition(App.neighbor(of: tiles[1], in: tiles, toward: .bottom, skip: 1) == 2)
        precondition(App.neighbor(of: tiles[1], in: tiles, toward: .left, skip: 1) == 0)
        precondition(App.neighbor(of: tiles[0], in: tiles, toward: .top, skip: 0) == nil)
        let leftHalf = CGRect(x: 0, y: 0, width: 500, height: 800), rightHalf = CGRect(x: 510, y: 0, width: 490, height: 800)
        precondition(App.neighborsResized(old: leftHalf, new: CGRect(x: 0, y: 0, width: 600, height: 800), others: [rightHalf, tiles[0]])
                     == [0: CGRect(x: 610, y: 0, width: 390, height: 800)])
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
        // h j k l add the space too, unless they start another trigger.
        r.text = "d"
        precondition(r.typeDirection("h") && r.text == "d h")
        r.text = "t"
        precondition(r.typeDirection("h") && r.text == "t h" && !r.typeDirection("x"))
        r.text = "h"
        precondition(!r.typeDirection("k")) // "hk" is the top-left corner, typed as usual
        r.text = ""
        precondition(!r.typeDirection("h"))
        var dh = d
        dh[dh.firstIndex { $0.id == "settings" }!].trigger = "dh"
        r.defs = { dh }
        r.text = "d"
        precondition(!r.typeDirection("h")) // "dh" is a trigger now
        r.defs = { d }
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
        precondition(Command.parse("+", d) == .resize(1) && Command.parse("-", d) == .resize(-1))
        precondition(Command.parse("re l", d) == .resizeEdge(CGSize(width: 1, height: 0)))
        precondition(Command.parse("re hh", d) == .resizeEdge(CGSize(width: -2, height: 0)))
        precondition(Command.parse("re →↓", d) == .resizeEdge(CGSize(width: 1, height: 1)))
        // Grow then shrink by the same step lands back on the original size.
        let unit = CGRect(x: 0, y: 0, width: 1000, height: 1000), steps = ResizeSteps(scale: 0.2, edge: 0.1)
        let grown = App.resized(CGRect(x: 100, y: 100, width: 400, height: 400), .resize(1), bounds: unit, steps: steps)!
        precondition(abs(grown.width - 480) < 0.001)
        precondition(abs(App.resized(grown, .resize(-1), bounds: unit, steps: steps)!.width - 400) < 0.001)
        precondition(App.resized(CGRect(x: 0, y: 0, width: 400, height: 400), .resizeEdge(CGSize(width: 2, height: 0)),
                                 bounds: unit, steps: steps)!.width == 600)
        // A window against the right side moves its left edge: h grows it, l shrinks it.
        let right = CGRect(x: 600, y: 0, width: 400, height: 1000)
        precondition(App.resized(right, .resizeEdge(CGSize(width: -1, height: 0)), bounds: unit, steps: steps)
                     == CGRect(x: 500, y: 0, width: 500, height: 1000))
        precondition(App.resized(right, .resizeEdge(CGSize(width: 2, height: 0)), bounds: unit, steps: steps)
                     == CGRect(x: 800, y: 0, width: 200, height: 1000))
        precondition(App.resized(right, .resizeEdge(CGSize(width: 9, height: 0)), bounds: unit, steps: steps)!.width == 100)
        precondition(App.resized(right, .resizeEdge(CGSize(width: -9, height: 0)), bounds: unit, steps: steps) == unit)
        // Full screen: l frees the left edge, h the right one; j frees the top.
        precondition(App.resized(unit, .resizeEdge(CGSize(width: 2, height: 0)), bounds: unit, steps: steps)
                     == CGRect(x: 200, y: 0, width: 800, height: 1000))
        precondition(App.resized(unit, .resizeEdge(CGSize(width: -1, height: 1)), bounds: unit, steps: steps)
                     == CGRect(x: 0, y: 100, width: 900, height: 900))
        // Against the bottom: k grows it up.
        precondition(App.resized(CGRect(x: 0, y: 500, width: 400, height: 500), .resizeEdge(CGSize(width: 0, height: -1)),
                                 bounds: unit, steps: steps) == CGRect(x: 0, y: 400, width: 400, height: 600))
        precondition(Command.parse("re x", d) == nil && Command.parse("re", d) == nil)
        precondition(Command.parse("t +", d) == nil)
        precondition(Command.parse("s j", d) == .scroll(CGSize(width: 0, height: 1)))
        precondition(Command.parse("s kk", d) == .scroll(CGSize(width: 0, height: -2)))
        precondition(Command.parse("s ↓", d) == .scroll(CGSize(width: 0, height: 1)) && Command.parse("s", d) == nil)
        // Scrolling runs as each key is typed, without Enter, and leaves "s " ready.
        let sp = Palette()
        sp.defs = { d }
        var scrolled: [Command] = []
        sp.live = { scrolled.append($0) }
        sp.text = "s "
        precondition(sp.scrollKey("j") && scrolled == [.scroll(CGSize(width: 0, height: 1))])
        precondition(sp.scrollKey("k") && scrolled.last == .scroll(CGSize(width: 0, height: -1)))
        sp.typeArrow("↑")
        precondition(scrolled.last == .scroll(CGSize(width: 0, height: -1)) && scrolled.count == 3 && sp.text == "s ")
        precondition(!sp.scrollKey("x")) // other keys type as usual
        sp.text = "s"
        precondition(sp.typeDirection("j") && sp.text == "s " && scrolled.count == 4) // no space needed
        sp.text = "o "
        precondition(!sp.scrollKey("j")) // only after the scroll command
        // Pointer: "mo " halves the screen per key, "ms " steps, uppercase nudges, Return clicks.
        precondition(Command.parse("mo", d) == .click(right: false, count: 1) && Command.parse("ms r", d) == .click(right: true, count: 1))
        precondition(Command.parse("mo 2", d) == .click(right: false, count: 2) && Command.parse("mo x", d) == nil)
        let pt = Palette()
        pt.defs = { d }
        pt.pointerStep = { 50 }
        pt.pointerPreview = { true }
        var moved: [Command] = []
        pt.live = { moved.append($0) }
        pt.screen = CGRect(x: 0, y: 100, width: 1000, height: 800)
        pt.text = "mo"
        precondition(pt.typeDirection("l") && pt.text == "mo " && pt.pointerArea == CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        precondition(moved.last == .pointerTo(CGPoint(x: 750, y: 500)))
        precondition(pt.pointerKey("k") && pt.pointerArea == CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        precondition(pt.layoutPreview == pt.pointerArea)
        pt.pointerPreview = { false }
        precondition(pt.layoutPreview == nil)
        pt.pointerPreview = { true }
        precondition(pt.pointerKey("H") && moved.last == .pointerBy(CGSize(width: -10, height: 0)))
        precondition(pt.pointerKey(" ") && pt.text == "mo " && pt.pointerArea == CGRect(x: 0, y: 0, width: 1, height: 1))
        precondition(moved.last == .pointerTo(CGPoint(x: 500, y: 500)))
        precondition(pt.pointerKey("k") && pt.pointerArea == CGRect(x: 0, y: 0, width: 1, height: 0.5))
        pt.enter()
        precondition(pt.pointerArea == CGRect(x: 0, y: 0, width: 1, height: 1))
        pt.text = "ms "
        precondition(pt.pointerKey("j") && moved.last == .pointerBy(CGSize(width: 0, height: 50)))
        precondition(!pt.pointerKey("x"))
        pt.text = "s "
        precondition(!pt.pointerKey("j")) // only after a pointer command
        // Resizes preview where the window will go.
        let rp = Palette()
        rp.defs = { d }
        rp.steps = { ResizeSteps() }
        rp.screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        rp.window = CGRect(x: 100, y: 100, width: 400, height: 400)
        rp.text = "re l"
        precondition(rp.layoutPreview == CGRect(x: 0.1, y: 0.1, width: 0.45, height: 0.4))
        rp.text = "o Safari"
        precondition(rp.layoutPreview == nil) // resizing isn't a place for a new tab window
        // A window that kept its size is centered in the target area, and stays on screen.
        let screen = CGRect(x: 0, y: 25, width: 1000, height: 800)
        precondition(App.center(CGSize(width: 400, height: 300), in: screen, bounds: screen) == CGPoint(x: 300, y: 275))
        precondition(App.center(CGSize(width: 400, height: 300), in: CGRect(x: 0, y: 25, width: 500, height: 800), bounds: screen) == CGPoint(x: 50, y: 275))
        precondition(App.center(CGSize(width: 600, height: 900), in: CGRect(x: 500, y: 25, width: 500, height: 800), bounds: screen) == CGPoint(x: 400, y: 25))
        // Smooth scroll frames add up to the whole distance and stop.
        var left: CGFloat = -263, frames = 0
        while App.scrollPart(left) != 0 { left -= CGFloat(App.scrollPart(left)); frames += 1 }
        precondition(abs(left) < 1 && frames < 40)
        // "b " lists running apps, filtered by what's typed; Enter switches to the highlighted one.
        let ap = Palette()
        ap.defs = { d }
        ap.apps = ["Discord", "Safari", "Safari Technology Preview", "Slack"].map { AppItem(name: $0) }
        var picked: String?
        ap.submit = { picked = $0 }
        ap.text = "b "
        precondition(ap.appMatches?.count == 4)
        ap.text = "b saf"
        precondition(ap.appMatches?.map(\.name) == ["Safari", "Safari Technology Preview"])
        ap.move(1)
        ap.text = "b saf" // same text written back on a redraw keeps the highlight
        ap.enter()
        precondition(picked == "b Safari Technology Preview")
        ap.text = "o saf"
        ap.installed = [AppItem(name: "Safari", path: "/Applications/Safari.app"), AppItem(name: "Slack", path: "/Applications/Slack.app")]
        precondition(ap.appMatches?.map(\.name) == ["Safari"]) // o lists installed apps
        ap.enter()
        precondition(picked == "o Safari")
        ap.text = "d 2"
        precondition(ap.appMatches == nil) // only after b and o
        precondition(App.installedApps().contains { $0.name == "Safari" })
        // Discarding input: Ctrl+W drops a word, Esc clears before it closes.
        let e = Palette()
        var closed = false
        e.cancel = { closed = true }
        e.text = "re ←↑→ "
        e.deleteWord()
        precondition(e.text == "re ")
        e.deleteWord()
        precondition(e.text == "")
        e.text = "o Saf"
        e.escape()
        precondition(e.text == "" && !closed)
        e.escape()
        precondition(closed)
        // Every default trigger is unique.
        precondition(Set(d.map(\.trigger)).count == d.count)
        print("selftest ok")
    }
}
