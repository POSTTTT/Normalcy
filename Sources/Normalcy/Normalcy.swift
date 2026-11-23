import AppKit
import Carbon
import Combine
import CoreAudio
import SwiftUI

// Commands (default triggers, editable in Settings):
//   o <app>        open/launch app            e.g. o Safari
//   t <app>        switch to running app      e.g. t saf
//   d <1-9|h|l>    go to desktop N / left / right
//   mwd <1-9|h|l>  move focused window to desktop N / left / right
//   mt [h|l|k|j|f|c]  move current tab to a new window, optionally placed with a layout
//   nt ct          new / close tab
//   tn tp          next / previous tab
//   ts <h|l>…      previous / next tab as each key is pressed
//   fw bk          forward / back, like a two-finger swipe
//   h l k j        window: left / right / top / bottom half
//   hh jk ll       window: left / center / right third
//   hl lh          window: left / right two thirds
//   f c            window: full / center
//   + -            window: 10% bigger / smaller, staying centered
//   re <h|l|k|j>…  window: narrower / wider / shorter / taller, one step per key
//   s <j|k|h|l>…   scroll the window down / up / left / right as each key is pressed
//   ar <h|j|k|l>…  press the left / down / up / right arrow key as each key is pressed
//   se <h|l|j>…    select a word before / after the cursor, or its line, as each key is pressed
//   cp cu pa sa    copy / cut / paste / select all
//   cp cu <h|l|j|a>  copy / cut to the word's start / end, the cursor's line, or everything
//   ls le          go to the start / end of the line
//   ds [h]         deselect, leaving the cursor at the selection's end (or start)
//   cpw cuw <h|l>  copy / cut the whole word the cursor is in, before or after it
//   cl <label>     click what that label sits on in the front window
//   vol [app] <set 0-100|h j k l…|m|out [device]>   volume, mute, output device; for one app with its name
//   pp nx pv       play / pause, next / previous track, in whatever is playing
//   ff rw          10 seconds forward / back
//   set            open settings
extension Command {
    var isLiveKeys: Bool {
        switch self { case .arrow, .pressKeys: true; default: false }
    }
}

struct KeyPress: Equatable {
    var key: CGKeyCode
    var flags: CGEventFlags
}

enum Command: Equatable {
    // The whole word, even from the middle of it: move to one end, then select to the other.
    // .left the word the cursor is in or just after, .right the one it's in or just before.
    static func wordKeys(_ dir: Action) -> [KeyPress]? {
        let arrow: CGEventFlags = [.maskNumericPad, .maskSecondaryFn]
        let (from, to): (CGKeyCode, CGKeyCode) // kVK_LeftArrow 123, kVK_RightArrow 124
        switch dir {
        case .left: (from, to) = (123, 124)
        case .right: (from, to) = (124, 123)
        default: return nil
        }
        return [KeyPress(key: from, flags: arrow.union(.maskAlternate)), KeyPress(key: to, flags: arrow.union([.maskAlternate, .maskShift]))]
    }

    // Keys that select, the way you would by hand: .left the word before the cursor (or one more
    // word, if a selection is going), .right the word after, .top / .bottom the whole line the
    // cursor is in, without its line break. Used by "cp" / "cu" with a direction, and by "se".
    static func selectKeys(_ dir: Action) -> [KeyPress]? {
        let arrow: CGEventFlags = [.maskNumericPad, .maskSecondaryFn]
        switch dir {
        case .left: return [KeyPress(key: 123, flags: arrow.union([.maskAlternate, .maskShift]))]
        case .right: return [KeyPress(key: 124, flags: arrow.union([.maskAlternate, .maskShift]))]
        case .top, .bottom: return [KeyPress(key: 123, flags: arrow.union(.maskCommand)),
                                    KeyPress(key: 124, flags: arrow.union([.maskCommand, .maskShift]))]
        default: return nil
        }
    }

    case open(String)
    case focus(String)
    case focusWindow(Action) // the nearest window on this desktop to the left / right / top / bottom
    case ctrlKey(CGKeyCode)
    case moveToDesktop(CGKeyCode)
    case tabToWindow(CGRect?) // optional layout for the new window
    case switchTab(next: Bool)
    case arrow(Action) // an arrow key: .left / .bottom / .top / .right
    case history(forward: Bool)
    case layout(CGRect) // fractions of the screen, top-left origin
    case resize(Int) // steps bigger (or smaller, if negative) around the window's center
    case resizeEdge(CGSize) // steps to move the right and bottom edges out (or in, if negative)
    case scroll(CGSize) // steps right and down (negative: left and up)
    case pointerTo(CGPoint) // global coordinates, top-left origin
    case pointerBy(CGSize) // points right and down
    case click(right: Bool, count: Int)
    case clickAt(CGPoint, right: Bool, count: Int) // global coordinates, top-left origin
    case keys(HotKey) // an app shortcut, pressed in the app in front
    case pressKeys([KeyPress]) // several keys in a row in the app in front, e.g. select a word then copy
    case volume(app: String?, VolumeChange) // nil: the whole Mac
    case media(Media)
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
        if let d = defs.first(where: { $0.enabled && ($0.names.contains(word) || arrowAction(word)?.rawValue == $0.id) }) {
            return d
        }
        // An arrow can stand in for its letter inside a trigger: "←3" = "h3" (left third).
        let spelled = word.map { ch in
            arrowAction(String(ch)).flatMap { a in defs.first { $0.id == a.rawValue }?.trigger } ?? String(ch)
        }.joined()
        if spelled != word, let d = defs.first(where: { $0.enabled && $0.names.contains(spelled) }) { return d }
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
        guard let head = parts.first, let def = lookup(head, in: defs) else { return nil }
        let arg = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        if let k = def.shortcut { return arg.isEmpty ? .keys(k) : nil }
        guard let action = Action(rawValue: def.id) else { return nil }
        switch action {
        case .open: return arg.isEmpty ? nil : .open(arg)
        case .focus:
            if let d = direction(arg, in: defs) { return .focusWindow(d) }
            return arg.isEmpty ? nil : .focus(arg)
        case .desktop: return desktopKey(arg, defs).map { .ctrlKey($0) }
        case .move: return desktopKey(arg, defs).map { .moveToDesktop($0) }
        case .left, .right, .top, .bottom, .full, .center, .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds,
             .topLeft, .topRight, .bottomLeft, .bottomRight:
            return layoutRect(action).map { .layout($0) }
        case .tab:
            if arg.isEmpty { return .tabToWindow(nil) }
            // Argument is a window-layout trigger, e.g. "t h" = new window on the left half.
            guard let d = lookup(arg, in: defs),
                  let rect = Action(rawValue: d.id).flatMap(layoutRect) else { return nil }
            return .tabToWindow(rect)
        // Cmd+T / Cmd+W in the app in front, the same path as an app shortcut.
        case .newTab: return .keys(HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey), label: "⌘T"))
        case .closeTab: return .keys(HotKey(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(cmdKey), label: "⌘W"))
        case .nextTab: return .switchTab(next: true)
        case .prevTab: return .switchTab(next: false)
        case .forward: return .history(forward: true)
        case .back: return .history(forward: false)
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
        // Cmd+C / X / V / A in the app in front, the same path as an app shortcut.
        // Cmd+Left / Right: the start or end of the line the cursor is in.
        case .lineStart, .lineEnd:
            return arg.isEmpty ? .pressKeys([KeyPress(key: action == .lineStart ? 123 : 124, flags: [.maskNumericPad, .maskSecondaryFn, .maskCommand])]) : nil
        // A plain arrow drops the highlight: "ds" leaves the cursor at the selection's end, "ds h" its start.
        case .deselect:
            let dir = arg.isEmpty ? .right : direction(arg, in: defs)
            guard dir == .left || dir == .right else { return nil }
            return .pressKeys([KeyPress(key: dir == .left ? 123 : 124, flags: [.maskNumericPad, .maskSecondaryFn])])
        case .copyWord, .cutWord:
            // "cpw h" / "cpw l": the whole word, even from the middle of it.
            guard let dir = direction(arg, in: defs), let select = wordKeys(dir) else { return nil }
            let copy = action == .copyWord
            return .pressKeys(select + [KeyPress(key: copy ? 8 : 7, flags: .maskCommand)]
                              + (copy ? [KeyPress(key: dir == .right ? 123 : 124, flags: [.maskNumericPad, .maskSecondaryFn])] : []))
        case .copy, .cut:
            let key: CGKeyCode = action == .copy ? 8 : 7 // kVK_ANSI_C, kVK_ANSI_X
            if arg.isEmpty { return .keys(HotKey(keyCode: UInt32(key), modifiers: UInt32(cmdKey), label: action == .copy ? "⌘ C" : "⌘ X")) }
            // "cp a": everything, by Cmd+A. Otherwise from the cursor to the word's start or end, or the line.
            let dir = arg == "a" ? .right : direction(arg, in: defs)
            guard let dir, let select = arg == "a" ? [KeyPress(key: 0, flags: .maskCommand)] : selectKeys(dir) else { return nil } // kVK_ANSI_A
            // After a copy, a plain arrow drops the highlight, leaving the cursor where it was: at the
            // end of the word before it, the start of the word after it, or the end of the line
            // (for "cp a", the end of the text).
            let unselect = action == .copy ? [KeyPress(key: dir == .right && arg != "a" ? 123 : 124, flags: [.maskNumericPad, .maskSecondaryFn])] : []
            return .pressKeys(select + [KeyPress(key: key, flags: .maskCommand)] + unselect)
        case .paste: return .keys(HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey), label: "⌘ V"))
        case .selectAll: return .keys(HotKey(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey), label: "⌘ A"))
        case .undo: return .keys(HotKey(keyCode: UInt32(kVK_ANSI_Z), modifiers: UInt32(cmdKey), label: "⌘ Z"))
        case .redo: return .keys(HotKey(keyCode: UInt32(kVK_ANSI_Z), modifiers: UInt32(cmdKey | shiftKey), label: "⇧ ⌘ Z"))
        case .arrows, .select: return nil // arrow keys are pressed as keys are typed; Return only closes the bar
        case .tabs: return nil // tabs switch as keys are pressed; Return only closes the bar
        case .hints: return nil // the labels live in the bar; it clicks once one is typed
        case .volume:
            guard let p = volumeParts(arg, defs) else { return nil }
            switch p.verb {
            case "set": return Int(p.rest).flatMap { (0...100).contains($0) ? .volume(app: p.app, .set($0)) : nil }
            case "m": return p.rest.isEmpty ? .volume(app: p.app, .mute) : nil
            case "out": return p.rest.isEmpty ? nil : .volume(app: p.app, .output(p.rest))
            default:
                // Up raises it, down lowers it, one step per key: "vol kk".
                guard p.rest.isEmpty, let n = volumeSteps(p.verb, defs) else { return nil }
                return .volume(app: p.app, .step(n))
            }
        case .playPause: return arg.isEmpty ? .media(.playPause) : nil
        case .nextTrack: return arg.isEmpty ? .media(.next) : nil
        case .prevTrack: return arg.isEmpty ? .media(.previous) : nil
        case .skipForward: return arg.isEmpty ? .media(.skip(10)) : nil
        case .skipBack: return arg.isEmpty ? .media(.skip(-10)) : nil
        case .settings: return .settings
        }
    }

    // "vol [app] verb [rest]": the app name is every word before the first verb (set, m, out, or
    // direction keys), so names with spaces work: "vol google chrome set 30".
    static func volumeParts(_ arg: String, _ defs: [CommandDef]) -> (app: String?, verb: String, rest: String)? {
        let words = arg.split(separator: " ").map(String.init)
        guard let i = words.firstIndex(where: { ["set", "m", "out"].contains($0) || volumeSteps($0, defs) != nil }) else { return nil }
        return (i == 0 ? nil : words[..<i].joined(separator: " "), words[i], words[(i + 1)...].joined(separator: " "))
    }

    // Each direction key is one step, summed: "ll" = two right, "lj" = one right and one down.
    // nil if empty or anything but a direction is typed.
    // Down and up keys only (j k, or ↓ ↑): -1 per down, +1 per up. nil if anything else is typed.
    static func volumeSteps(_ arg: String, _ defs: [CommandDef]) -> Int? {
        guard let s = directionSteps(arg, defs), s.width == 0,
              arg.allSatisfy({ [.top, .bottom].contains(direction(String($0), in: defs)) }) else { return nil }
        return Int(-s.height)
    }

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
        case .leftTwoThirds: CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1)
        case .rightTwoThirds: CGRect(x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 1)
        case .topLeft: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        default: nil
        }
    }

    // The areas left beside a half (the other half), a third (the other two, the far edge first)
    // or a quarter (the other three, beside it first, then below or above, then across);
    // [] for center and full.
    static func fillAreas(_ f: CGRect) -> [CGRect] {
        let near = { (a: CGFloat, b: CGFloat) in abs(a - b) < 0.001 }
        if near(f.width, 0.5), near(f.height, 0.5) {
            let x = 0.5 - f.minX, y = 0.5 - f.minY // the other column and row
            return [CGRect(x: x, y: f.minY, width: 0.5, height: 0.5), CGRect(x: f.minX, y: y, width: 0.5, height: 0.5),
                    CGRect(x: x, y: y, width: 0.5, height: 0.5)]
        }
        if near(f.height, 1), near(f.width, 1.0 / 3) {
            let thirds = [0.0, 1.0 / 3, 2.0 / 3].map { CGRect(x: $0, y: 0, width: 1.0 / 3, height: 1) }
            return (near(f.minX, 2.0 / 3) ? thirds : thirds.reversed()).filter { !near($0.minX, f.minX) }
        }
        if near(f.height, 1), f.width < 0.99 {
            if near(f.minX, 0) { return [CGRect(x: f.maxX, y: 0, width: 1 - f.maxX, height: 1)] }
            if near(f.maxX, 1) { return [CGRect(x: 0, y: 0, width: f.minX, height: 1)] }
        }
        if near(f.width, 1), f.height < 0.99 {
            if near(f.minY, 0) { return [CGRect(x: 0, y: f.maxY, width: 1, height: 1 - f.maxY)] }
            if near(f.maxY, 1) { return [CGRect(x: 0, y: 0, width: 1, height: f.minY)] }
        }
        return []
    }
}

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    // macOS keeps windows below the menu bar; the Dynamic Island has to reach the top edge.
    override func constrainFrameRect(_ r: NSRect, to screen: NSScreen?) -> NSRect { r }
}

final class App: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 780),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let palette = Palette()
    let preview = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let glowPanel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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
            ("General", "gearshape", AnyView(GeneralSettings()), 620),
            ("Commands", "command", AnyView(CommandSettings()), 680),
            ("Windows", "macwindow", AnyView(WindowSettings()), 680),
            ("App Shortcuts", "keyboard.badge.ellipsis", AnyView(AppShortcutSettings()), 520),
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
        // Opens on the desktop you're on, instead of switching back to the one it was last on.
        w.collectionBehavior = .moveToActiveSpace
        // Back out of Cmd+Tab and the Dock once Settings closes; openSettings puts it in.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            NSApp.setActivationPolicy(.accessory)
        }
        return w
    }()

    static let devIcon: NSImage? = Bundle.main.bundlePath.hasSuffix(".app") ? nil
        : Bundle.module.url(forResource: "AppIcon", withExtension: "png").flatMap(NSImage.init(contentsOf:))

    func applicationDidFinishLaunching(_ n: Notification) {
        // Never shown (Normalcy has no menu bar), but its shortcuts still work: Cmd+W closes Settings.
        let windowMenu = NSMenu()
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let item = NSMenuItem()
        item.submenu = windowMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(item)
        NSApp.mainMenu = mainMenu
        // The icon macOS shows for Normalcy, e.g. in alerts and app switchers. Normalcy.app carries
        // its own (scripts/build-app.sh); Bundle.module is only for swift run, and crashes in an .app.
        if let icon = Self.devIcon { NSApp.applicationIconImage = icon }
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        buildPanel()
        registerHotKey()
        Updater.shared.start()
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
            if let id = desks.currentID, let img = await Snapshot.capture(excluding: [panel, preview, glowPanel]) {
                palette.thumbs[id] = img
                // Wallpaper as it really renders; the file on disk isn't always readable.
                if let bare = await Snapshot.capture(excluding: [panel, preview, glowPanel], bare: true) { palette.wallpaper = bare }
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
        menu.addItem(withTitle: "Normalcy \(Updater.current ?? "development build")", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        // Shown only while a newer version is out; nothing installs until it's clicked.
        let update = menu.addItem(withTitle: "", action: #selector(installUpdate), keyEquivalent: "")
        update.target = self
        update.isHidden = true
        Updater.shared.$latest.sink { update.title = "Install Version \($0?.version ?? "")…"; update.isHidden = $0 == nil }.store(in: &subs)
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Normalcy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    // Settings shows how the install is going, and any error.
    @objc func installUpdate() {
        openSettings()
        Updater.shared.install()
    }

    @objc func openSettings() {
        let w = settingsWindow
        // Still open on another desktop, it would take you there; close it so it opens on this one.
        if w.isVisible && !w.isOnActiveSpace { w.orderOut(nil) }
        // Center on the screen you're working on, not the one it was last on.
        if let s = NSScreen.main, w.screen != s { w.setFrameOrigin(NSPoint(x: s.visibleFrame.midX, y: s.visibleFrame.midY)) }
        w.center()
        // A regular app while Settings is open, so Cmd+Tab (and the Dock) can bring it back.
        NSApp.setActivationPolicy(.regular)
        if let icon = Self.devIcon { NSApp.applicationIconImage = icon } // swift run: the Dock tile starts blank
        // The plain activate() is only a request, and macOS can turn it down once the bar has
        // hidden, leaving Settings behind the app in front.
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
    }

    func buildPanel() {
        palette.submit = { [weak self] text in
            guard let self else { return }
            let cmd = Command.parse(text, palette.defs())
            let fromBar = panel.isVisible // not `--run` from a script
            hide()
            guard let cmd else { return NSSound.beep() }
            let placedAX = focusedWindow()
            let placed = placedAX.flatMap { w -> CGWindowID? in
                var id: CGWindowID = 0
                return _AXUIElementGetWindow(w, &id) == .success ? id : nil
            }
            run(cmd)
            // A half or side third: offer this desktop's other windows for the space left over.
            if fromBar, case .layout(let f) = cmd {
                fillAreas = Command.fillAreas(f)
                fillTaken = Set([placed].compactMap { $0 })
                let round = fillRound
                whenSettled(placedAX) { self.offerFill(round) }
            }
        }
        palette.submitContinuing = { [weak self] text in
            guard let self, let cmd = Command.parse(text, palette.defs()) else { return NSSound.beep() }
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
            case .switchTab, .history: 0.35
            case .keys, .pressKeys: 0.6 // after pressAndConfirm's keys, up to 4 of them
            default: 0.2
            }
            scheduleRefocus(after: wait)
        }
        palette.cancel = { [weak self] in self?.hide() }
        palette.live = { [weak self] cmd in
            guard let self else { return }
            // Tab mode: the keys go straight to the app, which stays active behind the bar, so the
            // bar keeps focus and keeps taking keys. Activating the app would send the next key to it.
            if case .switchTab(let next) = cmd, let pid = target?.processIdentifier {
                if target == .current { return switchSettingsTab(next) }
                return pressKey(next ? 30 : 33, [.maskCommand, .maskShift], to: pid)
            }
            // ar / se in front of our own Settings would send the keys to the bar itself, and each
            // arrow would type another: the bar holds our keyboard, so there's nothing to do.
            if target == .current, cmd.isLiveKeys { return NSSound.beep() }
            if case .arrow(let dir) = cmd, let pid = target?.processIdentifier {
                return pressKey(Self.arrowKeyCode(dir), Self.arrowFlags, to: pid)
            }
            if case .pressKeys(let keys) = cmd, let pid = target?.processIdentifier {
                return keys.forEach { self.pressKey($0.key, $0.flags, to: pid) }
            }
            // d + left / right: the bar stays up for the next press, like Shift+Enter, and takes
            // focus back once the switch lands.
            if case .ctrlKey = cmd {
                continuing = true
                run(cmd)
                return scheduleRefocus(after: 1.5)
            }
            run(cmd)
        }
        // The front app's own shortcuts come first, so they win a trigger shared with a built-in.
        palette.defs = { [weak self] in Store.shared.defs(for: self?.target?.bundleIdentifier) }
        palette.loadHints = { [weak self] in self?.clickableFrames() ?? [] }
        // Next pass: the bar clears its text on hide, and the label was typed inside that text's didSet.
        palette.clickHint = { [weak self] cmd in DispatchQueue.main.async { self?.hide(); self?.run(cmd) } }
        // Labels go above the bar, so it doesn't hide the ones under it.
        palette.$hints.sink { [weak self] hints in
            guard let self, panel.isVisible else { return }
            preview.order(hints.isEmpty ? .below : .above, relativeTo: panel.windowNumber)
        }.store(in: &subs)
        palette.loadShots = { [weak self] ids in
            Task { @MainActor in await Snapshot.windows(ids) { self?.palette.windowShots[$0] = $1 } }
        }
        palette.pickWindow = { [weak self] w in
            guard let self else { return }
            let fill = palette.fill
            hide()
            if let fill, let ax = axWindow(w.pid, id: w.id) { place(fill, window: ax) }
            focus(w)
            // Quarters: on to the next empty one.
            if fill != nil {
                fillTaken.insert(w.id)
                let round = fillRound
                whenSettled(axWindow(w.pid, id: w.id)) { self.offerFill(round) }
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
        // Glow style's light: the full width of the screen, so it gets its own click-through panel.
        glowPanel.contentView = NSHostingView(rootView: EdgeGlow(model: palette))
        glowPanel.isOpaque = false
        glowPanel.backgroundColor = .clear
        glowPanel.hasShadow = false
        glowPanel.ignoresMouseEvents = true
        glowPanel.animationBehavior = .none
        glowPanel.level = .statusBar
        glowPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
        fillRound += 1 // the bar opened since: a fill picker still waiting is dropped
        target = NSWorkspace.shared.frontmostApplication
        // Chrome and Electron apps build their accessibility tree only when asked; ask now,
        // so it's ready by the time "cl " needs it.
        if let pid = target?.processIdentifier {
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        captureWindow()
        palette.apps = runningApps()
        palette.outputs = Self.outputItems()
        palette.installed = Self.installedApps()
        palette.text = ""
        palette.desktops = Desktops.read()
        loadWallpaper()
        snapshotDesktop()
        palette.windows = windowItems() // after snapshotDesktop, which updates `seen`
        palette.previousWindow = previousWindow(in: palette.windows)
        palette.windowShots = [:]
        // A screen-tall column; the view places its content inside by style and position.
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            // Dynamic Island hangs from the very top, over the menu bar, so the column reaches it.
            // Glow lights the very bottom edge, so its column reaches down over the Dock.
            let island = Store.shared.style == .island, glow = Store.shared.style == .glow
            panel.level = island || glow ? .statusBar : .floating
            let bottom = glow ? screen.frame.minY : v.minY, top = island ? screen.frame.maxY : v.maxY
            panel.setFrame(NSRect(x: v.midX - 300, y: bottom, width: 600, height: top - bottom), display: false)
            preview.setFrame(v, display: false) // same area window commands fill
            glowPanel.setFrame(NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: 220), display: false)
        }
        panel.makeKeyAndOrderFront(nil)
        if Store.shared.style == .glow { glowPanel.order(.below, relativeTo: panel.windowNumber) }
        DispatchQueue.main.async {
            // A pass later, so it has redrawn without the last command's box; below the bar.
            self.preview.order(.below, relativeTo: self.panel.windowNumber)
            self.palette.focusToken += 1
            withAnimation(.uiEaseOut(0.15)) { self.palette.visible = true }
        }
    }

    // Runs `then` once the window has stopped moving. macOS animates tiling, and the bar taking
    // focus mid-way stops the window short of its place. Gives up after about 1.5 s.
    func whenSettled(_ w: AXUIElement?, last: CGRect? = nil, tries: Int = 26, then: @escaping () -> Void) {
        // The first look waits 0.2 s, so a move that starts late isn't taken for one already done.
        DispatchQueue.main.asyncAfter(deadline: .now() + (last == nil ? 0.2 : 0.05)) {
            let now = w.flatMap(self.axFrame)
            if now == nil || (last != nil && now == last) || tries == 0 { return then() }
            self.whenSettled(w, last: now, tries: tries - 1, then: then)
        }
    }

    var fillRound = 0 // bumped each time the bar opens
    var fillAreas: [CGRect] = [] // after a half, third or quarter: the areas a picked window can go to
    var fillTaken = Set<CGWindowID>() // windows already placed in this round, left out of the list

    // The bar again, as "b " listing only the other windows on this desktop, for the first area
    // left with no window in it; picking one puts it there. Nothing to pick, every area already
    // has a window, or the switch command off: stays closed.
    func offerFill(_ round: Int) {
        // The bar was opened since (another command, typed meanwhile), or is up: too late to offer.
        guard round == fillRound, !panel.isVisible else { return }
        guard let b = palette.defs().first(where: { $0.enabled && $0.id == Action.focus.rawValue })?.trigger,
              let s = Self.screenBounds() else { return }
        let current = Desktops.read().currentID
        let here = windowItems().filter { $0.space == current && !fillTaken.contains($0.id) }
        let shown = Self.visibleWindows()
        let rest = fillAreas.first { r in
            let area = CGRect(x: s.minX + s.width * r.minX, y: s.minY + s.height * r.minY,
                              width: s.width * r.width, height: s.height * r.height)
            return !shown.contains { Self.fills($0.frame, area) }
        }
        guard let rest, !here.isEmpty else { return }
        show()
        palette.windows = here
        palette.previousWindow = here.first?.id
        palette.text = b + " "
        palette.fill = rest // after the text, whose change would clear it
        // The bar moves into the space to fill, so the windows offered show where they'll go.
        if let v = NSScreen.main?.visibleFrame {
            let area = NSRect(x: v.minX + v.width * rest.minX, y: v.maxY - v.height * rest.maxY,
                              width: v.width * rest.width, height: v.height * rest.height)
            let w = min(600, area.width)
            panel.setFrame(NSRect(x: area.midX - w / 2, y: area.minY, width: w, height: area.height), display: true)
        }
    }

    // A window sits in that area: mostly inside it, so a big window behind doesn't count, and
    // taking at least a quarter of it, so one shrunk with "re" still does.
    static func fills(_ w: CGRect, _ area: CGRect) -> Bool {
        let i = w.intersection(area), size = { (r: CGRect) in r.isNull ? 0 : r.width * r.height }
        return size(i) >= 0.25 * size(area) && size(i) >= 0.8 * size(w)
    }

    // Closing stays instant: a fading bar would get caught in a desktop switch.
    func hide() {
        steppedAside = false
        panel.orderOut(nil)
        preview.orderOut(nil)
        glowPanel.orderOut(nil)
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

    // Every window for "b ", under its desktop in order, then full-screen apps. Front to back
    // within a desktop. Windows on other desktops are listed
    // only once seen on screen, since apps' kept-around closed windows look just like them.
    func windowItems() -> [WindowItem] {
        let desks = Desktops.read()
        let all = Snapshot.windowsBySpace()
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0 != .current }
        let byPid = Dictionary(apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [WindowItem] = [], taken = Set<CGWindowID>()
        for space in desks.ids + all.keys.filter({ !desks.ids.contains($0) }).sorted() {
            let n = desks.ids.firstIndex(of: space)
            let group = n.map { "Desktop \($0 + 1)" + (space == desks.currentID ? " · Current" : "") } ?? "Full Screen"
            for w in all[space, default: []] where space == desks.currentID ? w.onScreen : seen.contains(w.id) {
                guard let app = byPid[w.pid], taken.insert(w.id).inserted else { continue } // a window on all desktops lists once
                out.append(WindowItem(id: w.id, pid: w.pid, app: app.localizedName ?? "", title: w.title, icon: app.icon, space: space, group: group))
            }
        }
        return out
    }

    // The window used before the one in front: the second one on this desktop, front to back,
    // else the front window of the app used before (on another desktop, say).
    // shortcut: stacking order stands in for when windows were used; track window focus if it guesses wrong.
    func previousWindow(in list: [WindowItem]) -> CGWindowID? {
        let current = Desktops.read().currentID
        let here = list.filter { $0.id != 0 && $0.space == current }
        if here.count > 1 { return here[1].id }
        let pid = recentApps.first { $0 != target?.processIdentifier && $0 != NSRunningApplication.current.processIdentifier }
        return list.first { $0.id != 0 && $0.pid == pid }?.id
    }

    // "b ": brings that window forward, going to its desktop first when it's on another.
    func focus(_ w: WindowItem) {
        guard let app = NSRunningApplication(processIdentifier: w.pid) else { return NSSound.beep() }
        let raise = { [weak self] in
            if let ax = self?.axWindow(w.pid, id: w.id) {
                AXUIElementSetAttributeValue(ax, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(ax, kAXRaiseAction as CFString)
            }
            app.unhide()
            app.activate()
        }
        let desks = Desktops.read()
        // Another app's windows are reachable through Accessibility only on the desktop on screen.
        if w.space != desks.currentID, let n = desks.ids.firstIndex(of: w.space), n < Command.digitKeys.count {
            run(.ctrlKey(Command.digitKeys[n]))
            // shortcut: fixed wait for the switch to land; lengthen if the window doesn't come forward.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: raise)
        } else {
            raise() // full screen, or past desktop 9: activating the app takes macOS to one of its windows
        }
    }

    func axWindow(_ pid: pid_t, id: CGWindowID) -> AXUIElement? {
        let ax: [AXUIElement] = axAttr(AXUIElementCreateApplication(pid), kAXWindowsAttribute) ?? []
        return ax.first { var wid: CGWindowID = 0; return _AXUIElementGetWindow($0, &wid) == .success && wid == id }
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

    var steppedAside = false // the bar hid for pressAndConfirm's keys and comes back on refocus

    func refocus() {
        continuing = false
        guard panel.isVisible || steppedAside else { return }
        steppedAside = false
        target = NSWorkspace.shared.frontmostApplication
        captureWindow()
        palette.apps = runningApps()
        palette.outputs = Self.outputItems()
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
            Self.runningApp(q)?.activate()
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
            let w = focusedWindow()
            guard macTile(f) else { return place(f) }
            // macOS's own tiling sometimes leaves the window where it was, e.g. once it was resized
            // by hand since it last tiled, or stops it mid-way; then put it there directly.
            whenSettled(w) { [weak self] in
                guard let self, let w, let b = Self.screenBounds(), let now = axFrame(w) else { return }
                if !Self.near(now, Self.frame(f, in: b)) { place(f, window: w) }
            }
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
        case .clickAt(let p, let right, let count):
            postMouse(.mouseMoved, p)
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
        case .switchTab(let next):
            if target == .current { return switchSettingsTab(next) }
            // Cmd+Shift+] / [: next / previous tab in Safari, Chrome, Firefox, Finder, Terminal and VS Code.
            pressInTarget(next ? 30 : 33, [.maskCommand, .maskShift]) // kVK_ANSI_RightBracket / LeftBracket
        case .arrow(let dir):
            pressInTarget(Self.arrowKeyCode(dir), Self.arrowFlags)
        case .pressKeys(let keys):
            pressAndConfirm(keys)
        case .keys(let k):
            pressAndConfirm([KeyPress(key: CGKeyCode(k.keyCode), flags: k.eventFlags)])
        case .history(let forward):
            // Cmd+] / [: what a two-finger swipe does in Safari, Chrome, Firefox and Finder.
            // There's no public API to post the swipe itself.
            pressInTarget(forward ? 30 : 33, .maskCommand)
        case .volume(let app, let change):
            runVolume(app: app, change)
        case .media(let m):
            Media.send(m)
        case .settings:
            openSettings()
        }
    }

    // kVK_LeftArrow, kVK_DownArrow, kVK_UpArrow, kVK_RightArrow
    static func arrowKeyCode(_ dir: Action) -> CGKeyCode {
        switch dir { case .left: 123; case .bottom: 125; case .top: 126; default: 124 }
    }
    // A real arrow key press carries these; some apps check for them.
    static let arrowFlags: CGEventFlags = [.maskNumericPad, .maskSecondaryFn]

    // Like pressInTarget, for several keys. Cmd+C / X / V among them shows "Copied", "Cut" or
    // "Pasted"; copy and cut only once the clipboard has changed, so with nothing selected, nothing shows.
    func pressAndConfirm(_ keys: [KeyPress]) {
        // After Shift+Return the bar is still up and holds the keyboard, so the app in front gets
        // the keys without its window focused: a page like Google Docs never sees them, and Safari
        // takes Cmd+→ as Forward. Step the bar aside; refocus brings it back.
        if continuing, panel.isVisible { steppedAside = true; panel.orderOut(nil) }
        let before = NSPasteboard.general.changeCount
        let edit = keys.first { $0.flags == .maskCommand && [7, 8, 9].contains($0.key) }?.key // kVK_ANSI_X, C, V
        activateTarget()
        // A gap between keys: browsers apply a selection in the page asynchronously, while Cmd+C
        // goes through the Edit menu at once, so without it the copy beats the selection.
        // shortcut: fixed 80 ms gaps; lengthen if a slow app still copies too early.
        let gap = 0.08, start = 0.15
        for (i, k) in keys.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + start + gap * Double(i)) { self.pressKey(k.key, k.flags) }
        }
        guard let edit else { return }
        // Then a wait for the app to fill the clipboard.
        DispatchQueue.main.asyncAfter(deadline: .now() + start + gap * Double(keys.count) + 0.25) {
            if edit == 9 { self.showToast("Pasted") }
            else if NSPasteboard.general.changeCount != before { self.showToast(edit == 8 ? "Copied" : "Cut") }
        }
    }

    // A short note at the bottom of the screen that fades on its own, like the volume HUD.
    lazy var toast: NSPanel = {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return p
    }()
    var toastHide: DispatchWorkItem?

    func showToast(_ text: String) {
        let view = NSHostingView(rootView: Text(text)
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .accessibilityLabel(text))
        toast.contentView = view
        let size = view.fittingSize
        if let v = NSScreen.main?.visibleFrame {
            toast.setFrame(NSRect(x: v.midX - size.width / 2, y: v.minY + 80, width: size.width, height: size.height), display: true)
        }
        toast.alphaValue = 1
        toast.orderFrontRegardless()
        NSAccessibility.post(element: toast, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        toastHide?.cancel()
        let hide = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; self?.toast.animator().alphaValue = 0 },
                                                 completionHandler: { if self?.toast.alphaValue == 0 { self?.toast.orderOut(nil) } })
        }
        toastHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: hide)
    }

    // Our own Settings doesn't take the keyboard back on its own once the bar is gone; hand it over.
    func activateTarget() {
        if target == .current, settingsWindow.isVisible { settingsWindow.makeKeyAndOrderFront(nil) }
        target?.activate()
    }

    // Same as .tabToWindow: give the app back key focus first, then press the keys.
    func pressInTarget(_ key: CGKeyCode, _ flags: CGEventFlags) {
        activateTarget()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.pressKey(key, flags) }
    }

    func pressKey(_ key: CGKeyCode, _ flags: CGEventFlags, to pid: pid_t? = nil) {
        if !AXIsProcessTrusted() { NSSound.beep(); print("Normalcy: grant Accessibility permission"); return }
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
            e?.flags = flags
            if let pid { e?.postToPid(pid) } else { e?.post(tap: .cghidEventTap) }
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
                    // A plain click, even with Shift still down from the last key (a capital label, or
                    // Shift+Return): Safari takes Shift+click on a link as "Add to Reading List".
                    e?.flags = []
                    e?.post(tap: .cghidEventTap)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.panel.ignoresMouseEvents = false }
        }
    }

    static let clickableRoles: Set<String> = [
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXComboBox",
        "AXTextField", "AXTextArea", "AXDisclosureTriangle", "AXRow",
    ]

    // The showing part of each clickable element in the front window, for "cl " labels.
    // An element is skipped when its middle is scrolled out of view; nothing inside it gets its own label.
    // shortcut: stops after 5000 elements and doesn't check for things covering it; raise if big pages miss labels.
    func clickableFrames() -> [CGRect] {
        guard let win = focusedWindow(), let wf = axFrame(win) else { return [] }
        let attrs = [kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute] as CFArray
        var out: [CGRect] = [], budget = 5000
        func walk(_ e: AXUIElement, _ clip: CGRect) {
            guard budget > 0 else { return }
            budget -= 1
            var vals: CFArray?
            // One round trip for all four, instead of four.
            guard AXUIElementCopyMultipleAttributeValues(e, attrs, [], &vals) == .success,
                  let v = vals as? [AnyObject], v.count == 4 else { return }
            let role = v[0] as? String ?? ""
            var origin = CGPoint.zero, size = CGSize.zero
            let hasFrame = CFGetTypeID(v[1]) == AXValueGetTypeID() && CFGetTypeID(v[2]) == AXValueGetTypeID()
                && AXValueGetValue(v[1] as! AXValue, .cgPoint, &origin) && AXValueGetValue(v[2] as! AXValue, .cgSize, &size)
            let f = hasFrame ? CGRect(origin: origin, size: size) : nil
            var clip = clip
            if role == "AXScrollArea" || role == "AXWebArea", let f { clip = clip.intersection(f) }
            if clip.isNull || clip.isEmpty { return }
            if Self.clickableRoles.contains(role) {
                if let f, f.width >= 4, f.height >= 4, clip.contains(CGPoint(x: f.midX, y: f.midY)) {
                    out.append(f.intersection(clip))
                }
                return
            }
            for kid in v[3] as? [AXUIElement] ?? [] { walk(kid, clip) }
        }
        walk(win, wf)
        return out
    }

    func postMouse(_ type: CGEventType, _ p: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    // Where to grab the window: the middle of the widest stretch of its title row with nothing
    // clickable in it. Apps drawing their own title bar (Claude, other Electron apps) put buttons
    // right of the green one; their drag area is the empty part.
    // shortcut: a stretch with nothing clickable is taken as draggable; a web app that marks empty
    // space no-drag won't move. Upgrade: try the next widest stretch if the window didn't follow.
    func titleBarPoint(_ w: AXUIElement) -> CGPoint? {
        guard let wf = axFrame(w) else { return nil }
        var zoom: CFTypeRef?
        let start: CGPoint
        if AXUIElementCopyAttributeValue(w, kAXZoomButtonAttribute as CFString, &zoom) == .success,
           let zoom, let f = axFrame(zoom as! AXUIElement) {
            start = CGPoint(x: f.maxX + 8, y: f.midY)
        } else {
            start = CGPoint(x: wf.minX + 90, y: wf.minY + 12)
        }
        func clickable(_ e: AXUIElement) -> Bool {
            var role: CFTypeRef?, acts: CFArray?
            AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &role)
            AXUIElementCopyActionNames(e, &acts)
            return Self.clickableRoles.contains(role as? String ?? "") || ((acts as? [String])?.contains("AXPress") ?? false)
        }
        // Safari's toolbar buttons hit-test as the bare window, so also block the frames of
        // clickable things near the top of the window's tree.
        var blocked: [CGRect] = []
        func walk(_ e: AXUIElement, _ depth: Int) {
            var kids: CFTypeRef?
            AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &kids)
            for k in kids as? [AXUIElement] ?? [] {
                guard let f = axFrame(k), f.minY <= start.y, f.maxY >= start.y else { continue }
                if clickable(k) { blocked.append(f) } else if depth < 3 { walk(k, depth + 1) }
            }
        }
        walk(w, 0)
        var pid: pid_t = 0
        AXUIElementGetPid(w, &pid)
        let sys = AXUIElementCreateSystemWide()
        let xs = Array(stride(from: start.x, to: wf.maxX - 8, by: 8))
        let free = xs.map { x -> Bool in
            guard !blocked.contains(where: { $0.minX <= x && x <= $0.maxX }) else { return false }
            var hit: AXUIElement?, elPid: pid_t = 0
            guard AXUIElementCopyElementAtPosition(sys, Float(x), Float(start.y), &hit) == .success, var el = hit,
                  AXUIElementGetPid(el, &elPid) == .success, elPid == pid else { return false }
            // A tab's icon or title isn't clickable itself; the tab around it is.
            for _ in 0..<5 {
                if clickable(el) { return false }
                var parent: CFTypeRef?
                guard AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parent) == .success,
                      let p = parent, CFGetTypeID(p) == AXUIElementGetTypeID() else { break }
                el = p as! AXUIElement
            }
            return true
        }
        return Self.widestRunMiddle(xs, free).map { CGPoint(x: $0, y: start.y) } ?? start
    }

    // Middle x of the longest run of true in free, nil if none.
    static func widestRunMiddle(_ xs: [CGFloat], _ free: [Bool]) -> CGFloat? {
        var best: Range<Int>?, from: Int?
        for i in 0...free.count {
            if i < free.count, free[i] { from = from ?? i; continue }
            if let f = from, (f..<i).count > (best?.count ?? 0) { best = f..<i }
            from = nil
        }
        return best.map { (xs[$0.lowerBound] + xs[$0.upperBound - 1]) / 2 }
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
    // Layouts macOS tiles itself, by their Window menu items. A window macOS tiled remembers that
    // tile and goes back to it after Mission Control, whatever size it was set to since; tiling
    // through macOS keeps what it remembers in step. Thirds and Center have no tile: placed directly.
    // shortcut: English menu titles only; other languages fall back to placing directly.
    static let macTiles: [(CGRect, [String])] = [
        (Action.full, ["Window", "Fill"]),
        (.left, ["Window", "Move & Resize", "Left"]), (.right, ["Window", "Move & Resize", "Right"]),
        (.top, ["Window", "Move & Resize", "Top"]), (.bottom, ["Window", "Move & Resize", "Bottom"]),
        (.topLeft, ["Window", "Move & Resize", "Top Left"]), (.topRight, ["Window", "Move & Resize", "Top Right"]),
        (.bottomLeft, ["Window", "Move & Resize", "Bottom Left"]), (.bottomRight, ["Window", "Move & Resize", "Bottom Right"]),
    ].map { (Command.layoutRect($0.0)!, $0.1) }

    func macTile(_ f: CGRect) -> Bool {
        Self.macTiles.first { $0.0 == f }.map { pressMenuPath($0.1) } ?? false
    }

    // Presses the menu item at that path (menu, submenu…, item), if it's there and enabled.
    func pressMenuPath(_ path: [String]) -> Bool {
        guard let pid = target?.processIdentifier,
              var e: AXUIElement = axAttr(AXUIElementCreateApplication(pid), kAXMenuBarAttribute) else { return false }
        for title in path {
            // An item's one child is its menu, whose children are the items.
            let kids: [AXUIElement] = axAttr(e, kAXChildrenAttribute) ?? []
            let items = kids.flatMap { k in (axAttr(k, kAXRoleAttribute) as String?) == kAXMenuRole ? (axAttr(k, kAXChildrenAttribute) ?? []) : [k] }
            guard let next = items.first(where: { (axAttr($0, kAXTitleAttribute) as String?) == title }) else { return false }
            e = next
        }
        guard (axAttr(e, kAXEnabledAttribute) as Bool?) == true else { return false }
        return AXUIElementPerformAction(e, kAXPressAction as CFString) == .success
    }

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
        // In front of our own Settings, the bar is the focused window; Settings is the main one.
        let attr = app == .current ? kAXMainWindowAttribute : kAXFocusedWindowAttribute
        guard AXUIElementCopyAttributeValue(ax, attr as CFString, &win) == .success,
              let win else { return nil }
        return (win as! AXUIElement)
    }

    // tn / tp / ts in our own Settings: its pages are toolbar tabs, which Cmd+Shift+] doesn't move.
    func switchSettingsTab(_ next: Bool) {
        guard let tabs = settingsWindow.contentViewController as? NSTabViewController else { return }
        let n = tabs.tabViewItems.count
        tabs.selectedTabViewItemIndex = (tabs.selectedTabViewItemIndex + (next ? 1 : -1) + n) % n
    }

    func place(_ f: CGRect, window: AXUIElement? = nil) {
        // shortcut: uses the screen with the panel, not the window's own screen; fix for multi-monitor
        guard let w = window ?? focusedWindow(), let screen = NSScreen.main, let primary = NSScreen.screens.first else { return }
        let v = screen.visibleFrame
        // AX uses top-left origin of the primary screen; AppKit uses bottom-left.
        let bounds = CGRect(x: v.minX, y: primary.frame.maxY - v.maxY, width: v.width, height: v.height)
        setFrame(w, Self.frame(f, in: bounds), bounds: bounds)
    }

    // A layout's fractions of the screen as a frame in that area.
    static func frame(_ f: CGRect, in b: CGRect) -> CGRect {
        CGRect(x: b.minX + b.width * f.minX, y: b.minY + b.height * f.minY, width: b.width * f.width, height: b.height * f.height)
    }

    // Every edge within 30 points: room for the margins macOS can leave around tiled windows.
    static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        [a.minX - b.minX, a.minY - b.minY, a.maxX - b.maxX, a.maxY - b.maxY].allSatisfy { abs($0) <= 30 }
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

// Private Accessibility API: an AX window's CGWindowID. Read-only, works with SIP on.
@_silgen_name("_AXUIElementGetWindow") func _AXUIElementGetWindow(_ e: AXUIElement, _ id: inout CGWindowID) -> AXError

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
        precondition(Command.parse("t saf", d) == .focus("saf"))
        precondition(Command.parse("t h", d) == .focusWindow(.left))
        precondition(Command.parse("t ho", d) == .focus("ho"))
        precondition(Command.parse("vol set 50", d) == .volume(app: nil, .set(50)))
        precondition(Command.parse("vol set 101", d) == nil)
        precondition(Command.parse("vol kk", d) == .volume(app: nil, .step(2)))
        precondition(Command.parse("vol j", d) == .volume(app: nil, .step(-1)))
        precondition(Command.parse("vol m", d) == .volume(app: nil, .mute))
        precondition(Command.parse("vol out", d) == nil)
        precondition(Command.parse("vol out MacBook Pro Speakers", d) == .volume(app: nil, .output("MacBook Pro Speakers")))
        precondition(Command.parse("vol google chrome set 30", d) == .volume(app: "google chrome", .set(30)))
        precondition(Command.parse("vol safari k", d) == .volume(app: "safari", .step(1)))
        precondition(Command.parse("vol h", d) == nil) // left and right don't change it; "h" is an app name
        precondition(Command.parse("vol safari out air", d) == .volume(app: "safari", .output("air")))
        precondition(Command.parse("vol safari", d) == nil)
        precondition(App.widestRunMiddle([0, 8, 16, 24, 32, 40], [true, false, true, true, true, false]) == 24)
        precondition(App.widestRunMiddle([0, 8], [false, false]) == nil && App.widestRunMiddle([0, 8], [true, true]) == 4)
        var broken = d
        broken[broken.firstIndex { $0.id == "left" }!].trigger = " "
        broken[broken.firstIndex { $0.id == "leftThird" }!].trigger = "  "
        broken[broken.firstIndex { $0.id == "top" }!].enabled = false
        let fixed = Store.repairDirections(broken)
        precondition(fixed.first { $0.id == "left" }?.trigger == "h" && fixed.first { $0.id == "leftThird" }?.trigger == "hh")
        precondition(fixed.first { $0.id == "top" }?.enabled == false && Store.repairDirections(d) == d)
        precondition(Command.parse("pp", d) == .media(.playPause) && Command.parse("nx", d) == .media(.next))
        precondition(Command.parse("ff", d) == .media(.skip(10)) && Command.parse("rw", d) == .media(.skip(-10)))
        precondition(Command.parse("ff 3", d) == nil)
        // Every tap output channel gets the tap's left, right, left, … at the gain.
        var src: [Float32] = [1, 2, 3, 4], dst = [Float32](repeating: 9, count: 6)
        src.withUnsafeMutableBytes { sb in dst.withUnsafeMutableBytes { db in
            var inList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: 16, mData: sb.baseAddress))
            var outList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: 24, mData: db.baseAddress))
            if #available(macOS 14.2, *) { AppRoute.copy(&inList, &outList, gain: 0.5) }
        } }
        precondition(dst == [0.5, 1, 1.5, 2, 0, 0]) // frames past the tap's are silent
        let tiles = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 200, y: 0, width: 100, height: 100),
                     CGRect(x: 200, y: 200, width: 100, height: 100), CGRect(x: 400, y: 150, width: 100, height: 100)]
        precondition(App.neighbor(of: tiles[0], in: tiles, toward: .right, skip: 0) == 1)
        precondition(App.neighbor(of: tiles[1], in: tiles, toward: .bottom, skip: 1) == 2)
        precondition(App.neighbor(of: tiles[1], in: tiles, toward: .left, skip: 1) == 0)
        precondition(App.neighbor(of: tiles[0], in: tiles, toward: .top, skip: 0) == nil)
        let leftHalf = CGRect(x: 0, y: 0, width: 500, height: 800), rightHalf = CGRect(x: 510, y: 0, width: 490, height: 800)
        precondition(App.neighborsResized(old: leftHalf, new: CGRect(x: 0, y: 0, width: 600, height: 800), others: [rightHalf, tiles[0]])
                     == [0: CGRect(x: 610, y: 0, width: 390, height: 800)])
        precondition(Command.fillAreas(Command.layoutRect(.left)!) == [Command.layoutRect(.right)!])
        precondition(Command.fillAreas(Command.layoutRect(.bottom)!) == [Command.layoutRect(.top)!])
        precondition(Command.fillAreas(Command.layoutRect(.rightThird)!) == [.leftThird, .centerThird].map { Command.layoutRect($0)! })
        precondition(Command.fillAreas(Command.layoutRect(.leftThird)!) == [.rightThird, .centerThird].map { Command.layoutRect($0)! })
        precondition(Command.fillAreas(Command.layoutRect(.centerThird)!).count == 2)
        precondition(Command.fillAreas(Command.layoutRect(.leftTwoThirds)!).map { [$0.minX, $0.width].map { ($0 * 3).rounded() } } == [[2, 1]])
        precondition(Command.fillAreas(Command.layoutRect(.rightTwoThirds)!) == [Command.layoutRect(.leftThird)!])
        var aka = d
        aka[aka.firstIndex { $0.id == "full" }!].aliases = "full max"
        precondition(Command.parse("full", aka) == .layout(Command.layoutRect(.full)!) && Command.parse("max", aka) == Command.parse("f", aka))
        precondition(Command.parse("full", d) == nil)
        precondition(Command.parse("hl", d) == .layout(Command.layoutRect(.leftTwoThirds)!))
        precondition(Command.parse("←→", d) == .layout(Command.layoutRect(.leftTwoThirds)!))
        precondition(Command.fillAreas(Command.layoutRect(.topLeft)!) == [.topRight, .bottomLeft, .bottomRight].map { Command.layoutRect($0)! })
        precondition(Command.fillAreas(Command.layoutRect(.bottomRight)!) == [.bottomLeft, .topRight, .topLeft].map { Command.layoutRect($0)! })
        precondition([.full, .center].allSatisfy { Command.fillAreas(Command.layoutRect($0)!).isEmpty })
        let rightArea = CGRect(x: 500, y: 0, width: 500, height: 800)
        precondition(App.fills(CGRect(x: 505, y: 0, width: 495, height: 800), rightArea))
        precondition(!App.fills(CGRect(x: 0, y: 0, width: 1000, height: 800), rightArea)) // full-screen window behind
        precondition(!App.fills(CGRect(x: 0, y: 0, width: 500, height: 800), rightArea)) // the placed half
        precondition(App.fills(CGRect(x: 500, y: 0, width: 300, height: 800), rightArea)) // shrunk with re
        precondition(App.frame(Command.layoutRect(.right)!, in: CGRect(x: 0, y: 25, width: 1000, height: 800))
                     == CGRect(x: 500, y: 25, width: 500, height: 800))
        precondition(App.near(CGRect(x: 508, y: 33, width: 484, height: 784), CGRect(x: 500, y: 25, width: 500, height: 800)))
        precondition(!App.near(CGRect(x: 600, y: 25, width: 400, height: 800), CGRect(x: 500, y: 25, width: 500, height: 800)))
        precondition(!App.fills(CGRect(x: 600, y: 300, width: 100, height: 100), rightArea)) // a small one
        precondition(Command.parse("d 2", d) == .ctrlKey(19))
        precondition(Command.parse("d l", d) == .ctrlKey(124))
        precondition(Command.parse("d 0", d) == nil)
        precondition(Command.parse("mwd 3", d) == .moveToDesktop(20))
        precondition(Command.parse("mwd h", d) == .moveToDesktop(123))
        precondition(Command.parse("mwd", d) == nil)
        precondition(Command.parse("h", d) == .layout(CGRect(x: 0, y: 0, width: 0.5, height: 1)))
        precondition(Command.parse("set", d) == .settings)
        precondition(Command.parse("mt", d) == .tabToWindow(nil))
        precondition(Command.parse("mt h", d) == .tabToWindow(CGRect(x: 0, y: 0, width: 0.5, height: 1)))
        precondition(Command.parse("mt f", d) == .tabToWindow(CGRect(x: 0, y: 0, width: 1, height: 1)))
        precondition(Command.parse("mt x", d) == nil)
        precondition(Command.parse("nt", d) == .keys(HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey), label: "⌘T")))
        precondition(Command.parse("ct", d) == .keys(HotKey(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(cmdKey), label: "⌘W")))
        precondition(Command.parse("tn", d) == .switchTab(next: true))
        precondition(Command.parse("tp", d) == .switchTab(next: false))
        precondition(Command.parse("fw", d) == .history(forward: true))
        precondition(Command.parse("bk", d) == .history(forward: false))
        precondition(Command.parse("mt o", d) == nil) // only layout triggers allowed
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
        p.text = "mwd h"
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
        precondition(Palette.spacedArrows("kkkkkkk") == "k×7" && Palette.spacedArrows("llj") == "llj")
        precondition(Palette.spacedArrows("lllhhh") == "l×3h×3")
        // Arrow keys type h j k l, adding the space after a command that takes a direction.
        let r = Palette()
        r.defs = { d }
        r.typeArrow("←")
        precondition(r.text == "←" && r.matches.first?.id == "left")
        precondition(Command.parse("←", d) == .layout(CGRect(x: 0, y: 0, width: 0.5, height: 1)))
        precondition(Command.parse("↓", d) == .layout(CGRect(x: 0, y: 0.5, width: 1, height: 0.5)))
        r.text = "mt"
        r.typeArrow("←")
        precondition(r.text == "mt ←")
        precondition(Command.parse("mt ←", d) == .tabToWindow(CGRect(x: 0, y: 0, width: 0.5, height: 1)))
        r.text = "mwd "
        r.typeArrow("→")
        precondition(r.text == "mwd →" && Command.parse("d →", d) == .ctrlKey(124)) // d's arrows go at once; see below
        // h j k l add the space too, unless they start another trigger.
        r.text = "mwd"
        precondition(r.typeDirection("h") && r.text == "mwd h")
        r.text = "mt"
        precondition(r.typeDirection("h") && r.text == "mt h" && !r.typeDirection("x"))
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
        q.text = "mt l"
        precondition(q.layoutPreview == CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        q.text = "o Safari"
        precondition(q.layoutPreview == nil)
        q.text = "ha" // no exact match; selected row "Left Half" (title match) still previews
        precondition(q.layoutPreview == CGRect(x: 0, y: 0, width: 0.5, height: 1))
        // Thirds and quarters, by trigger, by arrows, and after t.
        // Checked against plain numbers: CGRect also takes Ints, where 1 / 3 is 0.
        precondition(Command.layoutRect(.leftThird)!.width > 0.33 && Command.layoutRect(.leftThird)!.width < 0.34)
        precondition(Command.layoutRect(.rightThird)!.minX > 0.66)
        precondition(Command.parse("hh", d) == .layout(CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1)))
        precondition(Command.parse("ll", d) == .layout(CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)))
        precondition(Command.parse("hk", d) == .layout(CGRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        precondition(Command.parse("lj", d) == .layout(CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)))
        precondition(Command.parse("←↑", d) == Command.parse("hk", d))
        precondition(Command.parse("↑←", d) == Command.parse("hk", d))
        precondition(Command.parse("→↓", d) == Command.parse("lj", d))
        precondition(Command.parse("↓↓", d) == nil)
        precondition(Command.parse("kh", d) == Command.parse("hk", d))
        precondition(Command.parse("jl", d) == Command.parse("lj", d))
        precondition(Command.parse("h↑", d) == Command.parse("hk", d))
        precondition(Command.parse("kj", d) == nil) // up + down is no corner
        precondition(Command.parse("←←", d) == Command.parse("hh", d))
        precondition(Command.parse("→→", d) == Command.parse("ll", d))
        precondition(Command.parse("mt ←←", d) == .tabToWindow(Command.layoutRect(.leftThird)))
        precondition(Command.parse("mt kh", d) == .tabToWindow(CGRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        precondition(Command.parse("mt jk", d) == .tabToWindow(CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1)))
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
        precondition(trig(.leftThird, ijkl) == "jj" && trig(.bottomLeft, ijkl) == "jk" && trig(.topRight, ijkl) == "li")
        precondition(trig(.centerThird, ijkl) == "ki")
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
        h.text = "mt  "
        precondition(h.argPlaceholder == "nothing  new window\nh l k j f c  placed there") // one option per line, keys spelled
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
        precondition(HotKey.display("⇧⌘ K", symbols: false) == "Shift Command K")
        precondition(HotKey.display("⌥ Space", symbols: false) == "Option Space")
        precondition(HotKey.display("⌃ Return", symbols: true) == "⌃ ↩" && HotKey.display("Esc", symbols: true) == "⎋")
        precondition(HotKey.display("⇧⌘ K", symbols: true) == "⇧⌘ K" && HotKey.display("↩", symbols: false) == "Return")
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
        precondition(Command.parse("mt +", d) == nil)
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
        // "d" + left / right goes to that desktop at once, the key never typed; numbers still are.
        let dm = Palette()
        dm.defs = { d }
        var switched: [Command] = []
        dm.live = { switched.append($0) }
        dm.desktopInstant = { true } // not whatever Settings holds
        dm.text = "d"
        precondition(dm.typeDirection("l") && dm.text == "d " && switched == [.ctrlKey(124)])
        dm.typeArrow("←")
        precondition(switched.last == .ctrlKey(123) && dm.text == "d ")
        precondition(!dm.desktopKey("2") && !dm.desktopKey("j"))
        // Set to pick first: left / right move the highlight in the strip, Return goes there.
        dm.desktopInstant = { false }
        dm.desktops = Desktops(ids: [10, 20, 30], currentID: 20)
        var went: String?
        dm.submit = { went = $0 }
        dm.text = "d"
        precondition(dm.typeDirection("l") && dm.desktopTarget == 3 && switched.count == 2)
        precondition(dm.typeDirection("l") && dm.desktopTarget == 3) // stops at the last
        dm.typeArrow("←")
        dm.typeArrow("←")
        precondition(dm.desktopTarget == 1 && dm.text == "d ")
        dm.enter()
        precondition(went == "d 1")
        sp.text = "s"
        precondition(sp.typeDirection("j") && sp.text == "s " && scrolled.count == 4) // no space needed
        sp.text = "o "
        precondition(!sp.scrollKey("j")) // only after the scroll command
        // Volume mode: "vol " and "vol <app> " step the volume as keys are pressed.
        sp.volumeKeys = { "" } // the default, whatever this Mac's Settings say
        sp.text = "vol"
        precondition(sp.typeDirection("j") && sp.text == "vol " && scrolled.last == .volume(app: nil, .step(-1)))
        precondition(sp.typeDirection("k") && scrolled.last == .volume(app: nil, .step(1)))
        precondition(!sp.typeDirection("h") && !sp.typeDirection("l") && sp.text == "vol ") // only down and up
        sp.text = "vol google chrome "
        precondition(sp.typeDirection("k") && sp.text == "vol google chrome " && scrolled.last == .volume(app: "google chrome", .step(1)))
        sp.text = "vol set "
        precondition(!sp.typeDirection("j")) // types as usual after set, m and out
        sp.text = "vol saf"
        precondition(!sp.typeDirection("l")) // inside a name
        // Two keys of its own: only those (and arrows) step; h and l type an app name.
        sp.volumeKeys = { "-=" }
        sp.text = "vol"
        precondition(sp.typeDirection("=") && sp.text == "vol " && scrolled.last == .volume(app: nil, .step(1)))
        precondition(sp.typeDirection("-") && scrolled.last == .volume(app: nil, .step(-1)))
        precondition(!sp.typeDirection("h") && !sp.typeDirection("j"))
        sp.typeArrow("↓")
        precondition(scrolled.last == .volume(app: nil, .step(-1)) && sp.text == "vol ")
        sp.volumeKeys = { "all" } // both: h and j lower it, k and l raise it
        precondition(sp.typeDirection("h") && scrolled.last == .volume(app: nil, .step(-1)))
        precondition(sp.typeDirection("l") && scrolled.last == .volume(app: nil, .step(1)) && sp.text == "vol ")
        sp.volumeKeys = { "" }
        // Tab mode: "ts " switches tabs as left / right are pressed; up / down type as usual.
        sp.text = "ts"
        precondition(sp.typeDirection("l") && sp.text == "ts " && scrolled.last == .switchTab(next: true))
        sp.typeArrow("←")
        precondition(scrolled.last == .switchTab(next: false) && sp.text == "ts ")
        precondition(!sp.tabKey("j") && !sp.tabKey("x"))
        // Arrow mode: "ar " presses an arrow key for each direction key; other keys type as usual.
        sp.text = "ar"
        precondition(sp.typeDirection("j") && sp.text == "ar " && scrolled.last == .arrow(.bottom))
        sp.typeArrow("←")
        precondition(scrolled.last == .arrow(.left) && sp.text == "ar " && !sp.arrowKey("x"))
        sp.text = "se"
        precondition(sp.typeDirection("l") && sp.text == "se " && scrolled.last == .pressKeys(Command.selectKeys(.right)!))
        precondition(sp.arrowKey("k") && scrolled.last == .pressKeys(Command.selectKeys(.top)!))
        precondition(Command.parse("cp", d) == .keys(HotKey(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey), label: "⌘ C")))
        let opt: CGEventFlags = [.maskNumericPad, .maskSecondaryFn, .maskAlternate, .maskShift]
        let plain: CGEventFlags = [.maskNumericPad, .maskSecondaryFn]
        let move: CGEventFlags = [.maskNumericPad, .maskSecondaryFn, .maskAlternate]
        precondition(Command.parse("cp h", d) == .pressKeys([KeyPress(key: 123, flags: opt), KeyPress(key: 8, flags: .maskCommand), KeyPress(key: 124, flags: plain)]))
        precondition(Command.parse("cpw h", d) == .pressKeys([KeyPress(key: 123, flags: move), KeyPress(key: 124, flags: opt), KeyPress(key: 8, flags: .maskCommand), KeyPress(key: 124, flags: plain)]))
        precondition(Command.parse("cpw l", d) == .pressKeys([KeyPress(key: 124, flags: move), KeyPress(key: 123, flags: opt), KeyPress(key: 8, flags: .maskCommand), KeyPress(key: 123, flags: plain)]))
        precondition(Command.parse("ds", d) == .pressKeys([KeyPress(key: 124, flags: [.maskNumericPad, .maskSecondaryFn])]))
        precondition(Command.parse("ds h", d) == .pressKeys([KeyPress(key: 123, flags: [.maskNumericPad, .maskSecondaryFn])]))
        precondition(Command.parse("ds j", d) == nil)
        precondition(Command.parse("ls", d) == .pressKeys([KeyPress(key: 123, flags: [.maskNumericPad, .maskSecondaryFn, .maskCommand])]))
        precondition(Command.parse("le", d) == .pressKeys([KeyPress(key: 124, flags: [.maskNumericPad, .maskSecondaryFn, .maskCommand])]))
        precondition(Command.parse("cpw", d) == nil && Command.parse("cpw j", d) == nil)
        precondition(Command.parse("cu →", d) == .pressKeys([KeyPress(key: 124, flags: opt), KeyPress(key: 7, flags: .maskCommand)]))
        precondition(Command.parse("cuw →", d) == .pressKeys([KeyPress(key: 124, flags: move), KeyPress(key: 123, flags: opt), KeyPress(key: 7, flags: .maskCommand)]))
        if case .pressKeys(let k) = Command.parse("cp j", d) { precondition(k.count == 4 && k.last?.key == 124) } else { preconditionFailure() }
        precondition(Command.parse("cp a", d) == .pressKeys([KeyPress(key: 0, flags: .maskCommand), KeyPress(key: 8, flags: .maskCommand), KeyPress(key: 124, flags: plain)]))
        precondition(Command.parse("cu a", d) == .pressKeys([KeyPress(key: 0, flags: .maskCommand), KeyPress(key: 7, flags: .maskCommand)]))
        precondition(Command.parse("cp k", d) == Command.parse("cp j", d) && Command.parse("cp x", d) == nil)
        precondition(Command.parse("sa", d) == .keys(HotKey(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey), label: "⌘ A")))
        precondition(Command.parse("ar", d) == nil && Command.parse("ar h", d) == nil)
        // Shift+Return on a slip ("ar i") clears it for the next command instead of beeping.
        sp.text = "ar i"
        sp.enter(continuing: true)
        precondition(sp.text == "")
        sp.text = "se "
        // Return closes the bar without switching again; tn / tp still step one tab.
        var tabClosed = false, tabSubmitted: [String] = []
        sp.cancel = { tabClosed = true }
        sp.submit = { tabSubmitted.append($0) }
        sp.enter()
        precondition(tabClosed && tabSubmitted.isEmpty && Command.parse("ts", d) == nil)
        sp.text = "tp"
        precondition(!sp.typeDirection("h") && sp.text == "tp") // h types as usual after tp
        // Pointer: "mo " halves the screen per key, "ms " steps, uppercase nudges, Return clicks.
        precondition(Command.parse("mo", d) == .click(right: false, count: 1) && Command.parse("ms r", d) == .click(right: true, count: 1))
        precondition(Command.parse("mo 2", d) == .click(right: false, count: 2) && Command.parse("mo x", d) == nil)
        let ctrlC = HotKey(keyCode: 8, modifiers: UInt32(controlKey), label: "⌃ C")
        let ghostty = [CommandDef(id: "a", trigger: "cp", shortcut: ctrlC), CommandDef(id: "b", trigger: "cl", shortcut: ctrlC)] + d
        precondition(Command.parse("cp", ghostty) == .keys(ctrlC) && Command.parse("cp x", ghostty) == nil)
        precondition(Command.parse("cl", ghostty) == .keys(ctrlC)) // the app's trigger wins over a built-in
        precondition(Command.parse("cp", d) != .keys(ctrlC)) // elsewhere cp is the built-in Copy
        precondition(ctrlC.eventFlags == .maskControl)
        precondition(HotKey(keyCode: 0, modifiers: UInt32(cmdKey | shiftKey), label: "").eventFlags == [.maskCommand, .maskShift])
        precondition(ghostty[0].title == HotKey.display("⌃ C") && CommandDef(id: "a", trigger: "cp", name: "Close process").title == "Close process")
        precondition(Updater.isNewer("0.3.0", than: "0.2.0") && Updater.isNewer("0.10.0", than: "0.9.1"))
        precondition(!Updater.isNewer("0.2.0", than: "0.2.0") && !Updater.isNewer("0.2", than: "0.2.0") && !Updater.isNewer("0.1.9", than: "0.2.0"))
        let rel = #"{"tag_name":"v0.3.0","html_url":"https://github.com/POSTTTT/Normalcy/releases/tag/v0.3.0","assets":[{"name":"notes.txt","browser_download_url":"https://github.com/x"},{"name":"Normalcy-0.3.0.zip","browser_download_url":"https://github.com/POSTTTT/Normalcy/releases/download/v0.3.0/Normalcy-0.3.0.zip"}]}"#
        precondition(Updater.parse(Data(rel.utf8))?.version == "0.3.0" && Updater.parse(Data(rel.utf8))?.zip.lastPathComponent == "Normalcy-0.3.0.zip")
        precondition(Updater.parse(Data(rel.replacingOccurrences(of: "https://github.com/POSTTTT", with: "http://evil.example").utf8)) == nil)
        precondition(Updater.parse(Data("{}".utf8)) == nil)
        let hp = Palette()
        hp.defs = { d }
        var clicked: [Command] = []
        hp.clickHint = { clicked.append($0) }
        hp.loadHints = { [CGRect(x: 100, y: 50, width: 20, height: 10), CGRect(x: 0, y: 0, width: 40, height: 20)] }
        hp.text = "cl "
        precondition(hp.hints.map(\.label) == ["a", "s"] && hp.hints[0].frame.minY == 0) // top first
        hp.text = "cl q"
        precondition(hp.text == "cl " && clicked.isEmpty) // no such label: key dropped
        hp.text = "cl s"
        precondition(clicked == [.clickAt(CGPoint(x: 110, y: 55), right: false, count: 1)])
        hp.text = "cl r"
        precondition(hp.visibleHints.count == 2) // r is a right-click, not a label
        hp.text = "cl ra"
        precondition(clicked.last == .clickAt(CGPoint(x: 20, y: 10), right: true, count: 1))
        hp.text = "cl 2a"
        precondition(clicked.last == .clickAt(CGPoint(x: 20, y: 10), right: false, count: 2))
        hp.text = ""
        precondition(hp.hints.isEmpty)
        var ran: [String] = []
        hp.submitContinuing = { ran.append($0) }
        for t in ["s ", "re ", "cl ", "cl a"] {
            hp.text = t
            hp.enter(continuing: true)
            precondition(hp.text == "" && ran.isEmpty, t) // Shift+Enter finishes the mode, bar stays
        }
        hp.text = "d 0"
        hp.enter(continuing: true)
        precondition(ran == ["d 0"] && hp.text == "") // a wrong argument still goes through to beep, then clears
        let many = Palette.labeled((0..<30).map { CGRect(x: CGFloat($0), y: 0, width: 1, height: 1) })
        precondition(many.count == 30 && many[0].label == "aa" && many[9].label == "sa" && Set(many.map(\.label)).count == 30)
        precondition(Palette.labeled([]).isEmpty)
        let pt = Palette()
        pt.defs = { d }
        pt.pointerStep = { 50 }
        pt.pointerPreview = { true }
        pt.pointerKeys = { "" }
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
        pt.text = "mo "
        precondition(pt.pointerKey("h") && pt.pointerArea.width == 0.5)
        pt.escape()
        precondition(pt.text == "" && pt.pointerArea == CGRect(x: 0, y: 0, width: 1, height: 1)) // Esc starts over too
        pt.text = "ms "
        precondition(pt.pointerKey("j") && moved.last == .pointerBy(CGSize(width: 0, height: 50)))
        precondition(!pt.pointerKey("x"))
        pt.text = "s "
        precondition(!pt.pointerKey("j")) // only after a pointer command
        // mo / ms with their own keys (W A S D): those move, h j k l are typed as usual.
        pt.pointerKeys = { "aswd" }
        pt.text = "mo"
        precondition(pt.typeDirection("d") && pt.text == "mo " && pt.pointerArea == CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        precondition(pt.pointerKey("w") && pt.pointerArea == CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        precondition(!pt.pointerKey("l") && pt.pointerKey("→")) // arrows always work
        precondition(pt.pointerKey("S") && moved.last == .pointerBy(CGSize(width: 0, height: 10)))
        pt.text = "mwd"
        precondition(pt.typeDirection("h") && pt.text == "mwd h") // other commands keep the window keys
        pt.pointerKeys = { "" }
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
        // "t " lists every window under its desktop, filtered by app name or title; direction keys
        // move around the grid and Enter switches to the highlighted window.
        let ap = Palette()
        ap.defs = { d }
        ap.apps = ["Discord", "Safari", "Safari Technology Preview", "Slack"].map { AppItem(name: $0) }
        ap.windows = [WindowItem(id: 1, pid: 1, app: "Discord", group: "Desktop 1"),
                      WindowItem(id: 2, pid: 2, app: "Safari", title: "Apple", group: "Desktop 1"),
                      WindowItem(id: 3, pid: 2, app: "Safari", title: "GitHub", group: "Desktop 2"),
                      WindowItem(id: 4, pid: 3, app: "Slack", group: "Full Screen")]
        var picked: String?, pickedWindow: CGWindowID?
        ap.submit = { picked = $0 }
        ap.pickWindow = { pickedWindow = $0.id }
        ap.text = "t "
        precondition(ap.windowMatches?.count == 4 && ap.appMatches == nil)
        precondition(Palette.gridRows(ap.windowMatches!) == [[0, 1], [2], [3]])
        precondition(ap.typeDirection("j") && ap.selected == 2 && ap.text == "t ") // down a row, not typed
        precondition(ap.typeDirection("k") && ap.selected == 0)
        precondition(ap.typeDirection("l") && ap.selected == 1)
        precondition(ap.typeDirection("j") && ap.selected == 2) // the row below is shorter
        precondition(ap.typeDirection("l") && ap.selected == 3 && !ap.typeDirection("x"))
        ap.text = "t git"
        precondition(ap.windowMatches?.map(\.id) == [3]) // by title
        ap.text = "t saf"
        precondition(ap.windowMatches?.map(\.id) == [2, 3])
        ap.move(1)
        ap.text = "t saf" // same text written back on a redraw keeps the highlight
        ap.enter()
        precondition(pickedWindow == 3)
        ap.previousWindow = 3
        ap.text = "t "
        precondition(ap.selected == 2) // starts on the previous window, like Cmd+Tab
        ap.text = "t s"
        precondition(ap.selected == 0) // a name typed: the best match
        ap.previousWindow = nil
        ap.text = "t"
        precondition(ap.typeDirection("l") && ap.text == "t l" && ap.windowMatches == nil) // still the nearest window
        ap.text = "o saf"
        ap.installed = [AppItem(name: "Safari", path: "/Applications/Safari.app"), AppItem(name: "Slack", path: "/Applications/Slack.app")]
        precondition(ap.appMatches?.map(\.name) == ["Safari"]) // o lists installed apps
        ap.enter()
        precondition(picked == "o Safari")
        ap.outputs = ["AirPods", "MacBook Pro Speakers"].map { AppItem(name: $0) }
        ap.currentOutput = { $0 == nil ? "MacBook Pro Speakers" : "AirPods" }
        ap.text = "vol out "
        precondition(ap.appMatches?.map(\.current) == [false, true])
        ap.text = "vol safari out "
        precondition(ap.appMatches?.map(\.current) == [true, false])
        ap.text = "vol out m"
        precondition(ap.appMatches?.map(\.name) == ["MacBook Pro Speakers"])
        ap.enter()
        precondition(picked == "vol out MacBook Pro Speakers")
        ap.text = "vol google chrome out "
        precondition(ap.appMatches?.count == 2)
        ap.enter()
        precondition(picked == "vol google chrome out AirPods")
        ap.text = "vol set 5"
        precondition(ap.appMatches == nil)
        ap.text = "vol saf"
        precondition(ap.appMatches?.map(\.name) == ["Safari", "Safari Technology Preview"] && ap.appMatches?.first?.pid == 0)
        ap.enter()
        precondition(ap.text == "vol Safari ") // filled in, ready for h j k l
        ap.text = "vol "
        precondition(ap.appMatches == nil) // the list waits for a name
        var asked: [String?] = []
        ap.volumeInfo = { asked.append($0); return nil }
        for t in ["vol", "vol ", "vol se", "vol saf", "vol google chrome j", "vol out a", "t saf"] { ap.text = t; _ = ap.volumeShown }
        // Picking a window to fill the space left: the bar shows only the name typed, no "t" or options.
        ap.text = "t "
        ap.fill = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        precondition(ap.shownText == "" && ap.argPlaceholder == nil)
        ap.text = "t saf"
        precondition(ap.shownText == "saf" && ap.fill != nil)
        ap.text = ""
        precondition(ap.fill == nil && ap.shownText == "")
        precondition(asked == [nil, nil, nil, "saf", "google chrome"]) // not after "vol out" (levels are in the list) or b
        ap.text = "d 2"
        precondition(ap.appMatches == nil) // only after b, o and vol out
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
