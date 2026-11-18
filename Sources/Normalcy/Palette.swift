import SwiftUI

// A running app (pid set) for the switch list, or an installed one (path set) for the open list.
struct Hint: Equatable {
    var label: String
    var frame: CGRect // AX coordinates
}

struct AppItem: Equatable {
    var name: String
    var icon: NSImage?
    var pid: pid_t = 0
    var path: String?
    var current = false // "vol out": the device sound plays on now
    var symbol: String? // "vol out": the device's kind, as an SF Symbol; set only for devices
    var level: Float? // "vol out": the device's volume, 0-1; nil when it has none
}

// A window in the "b " grid. id 0 stands for a running app with no window open.
struct WindowItem: Equatable {
    var id: CGWindowID = 0
    var pid: pid_t
    var app: String
    var title = ""
    var icon: NSImage?
    var space = 0 // space ID; 0 for an app with no window
    var group: String // section it's listed under: "Desktop 2", "Full Screen", "No Windows"
    var hidden = false // an app hidden with Cmd+H
}

final class Palette: ObservableObject {
    // The highlight goes back to the top only when the text really changes: the text field
    // also writes back the same value when the view redraws (e.g. a preview arriving).
    // Any change also gives mo the whole screen again: keys inside mo never change the text.
    @Published var text = "" { didSet { if text != oldValue { selected = initialSelection; desktopPick = nil; pointerArea = CGRect(x: 0, y: 0, width: 1, height: 1); updateHints() } } }
    var live: (Command) -> Void = { _ in }
    @Published var apps: [AppItem] = [] // running apps, by name; refreshed when the bar opens
    var installed: [AppItem] = [] // apps in the Applications folders, by name
    var outputs: [AppItem] = [] // sound output devices, for "vol out"; refreshed when the bar opens
    var volumeInfo: (String?) -> VolumeInfo? = App.volumeInfo
    var currentOutput: (String?) -> String? = App.currentOutput // the Mac's, or that app's
    @Published var windows: [WindowItem] = [] // every window on every desktop, for "b "; refreshed when the bar opens
    @Published var windowShots: [CGWindowID: NSImage] = [:] // window -> its picture, taken when the grid shows
    var loadShots: ([CGWindowID]) -> Void = { _ in }
    var pickWindow: (WindowItem) -> Void = { _ in }
    var previousWindow: CGWindowID? // the one used before the front one; "b " starts on it, like Cmd+Tab
    @Published var selected = 0
    @Published var focusToken = 0 // bumped on every show to refocus the field
    @Published var visible = false // drives the entrance; reset while hidden so each open animates
    var submit: (String) -> Void = { _ in }
    var submitContinuing: (String) -> Void = { _ in } // runs, keeping the bar open for the next command
    var cancel: () -> Void = {}
    var defs: () -> [CommandDef] = { Store.shared.defs }
    @Published var desktops = Desktops()
    @Published var desktopPick: Int? // "d " when picking first: the desktop left / right have moved to, 1-based
    var desktopInstant: () -> Bool = { Store.shared.desktopInstant }
    @Published var thumbs: [Int: NSImage] = [:] // space ID -> last snapshot
    @Published var wallpaper: NSImage? // stand-in for desktops not yet snapshotted
    var window: CGRect? // target window and screen, AX coordinates, captured when the bar opens
    var screen: CGRect?
    var steps: () -> ResizeSteps = { Store.shared.resizeSteps }
    var pointerStep: () -> CGFloat = { CGFloat(Store.shared.pointerStep) } // points per key after "ms "
    var pointerPreview: () -> Bool = { Store.shared.pointerPreview } // box around what's left after "mo "
    var volumeKeys: () -> String = { Store.shared.volumeKeys } // down, up after vol; "" = the window's down and up, "all" = all four
    var pointerKeys: () -> String = { Store.shared.pointerKeys } // left, down, up, right for mo / ms; "" = the window keys
    // What's left of the screen after "mo " halvings, as fractions; whole again on Return,
    // Space, or any change to the text (Esc, another command, the bar closing).
    @Published var pointerArea = CGRect(x: 0, y: 0, width: 1, height: 1)
    // After "cl ": a label on each clickable thing in the front window, read once each time "cl " is typed.
    @Published var hints: [Hint] = []
    var loadHints: () -> [CGRect] = { [] } // AX coordinates
    var clickHint: (Command) -> Void = { _ in }

    // The desktop-related command being typed or highlighted, if any.
    var desktopCommand: CommandDef? {
        let rows = matches
        let row = text.drop { $0 == " " }.contains(" ") ? rows.first
            : rows.indices.contains(selected) ? rows[selected] : nil
        return row.flatMap { ["desktop", "move"].contains($0.id) ? $0 : nil }
    }

    // Desktop number the typed argument points at ("2", or "h"/"l" relative to the current one).
    // Screen area (fractions, top-left origin) the typed or highlighted window command would use.
    var layoutPreview: CGRect? {
        if pointerMode == .pointer { return pointerPreview() && (pointerArea.width < 1 || pointerArea.height < 1) ? pointerArea : nil }
        switch Command.parse(text, defs()) {
        case .layout(let r): return r
        case .tabToWindow(let r): return r
        case let cmd? where window != nil && screen != nil:
            // Resize commands: where the window will end up, as a fraction of the screen.
            guard let s = screen, let r = App.resized(window!, cmd, bounds: s, steps: steps()) else { return nil }
            return CGRect(x: (r.minX - s.minX) / s.width, y: (r.minY - s.minY) / s.height,
                          width: r.width / s.width, height: r.height / s.height)
        case nil:
            // Nothing complete typed yet: preview the highlighted row if it's a layout.
            let rows = matches
            guard !text.contains(" "), rows.indices.contains(selected),
                  let a = Action(rawValue: rows[selected].id) else { return nil }
            return Command.layoutRect(a)
        default: return nil
        }
    }

    var desktopTarget: Int? {
        if desktopMode, let p = desktopPick { return p }
        let parts = text.split(separator: " ")
        guard parts.count > 1 else { return nil }
        if let n = Int(parts[1]) { return n }
        guard let c = desktops.current else { return nil }
        switch Command.direction(String(parts[1]), in: defs()) {
        case .left: return c - 1
        case .right: return c + 1
        default: return nil
        }
    }

    // No space typed yet: filter by trigger (exact, then prefix) or title. After a space: only the exact trigger.
    var matches: [CommandDef] {
        let defs = self.defs().filter(\.enabled)
        let s = text.drop { $0 == " " }
        // Nothing typed: the named commands first, then the window commands, so the grid style
        // shows one block of rows above one grid.
        guard let head = s.split(separator: " ").first.map(String.init) else {
            let isWindow = { (d: CommandDef) in Action(rawValue: d.id)?.isWindow == true }
            return defs.filter { !isWindow($0) } + defs.filter(isWindow)
        }
        if s.contains(" ") { return defs.filter { $0.trigger == head } }
        let exact = Command.lookup(head, in: defs).map { [$0] } ?? []
        let prefix = defs.filter { $0.trigger != head && $0.trigger.hasPrefix(head) && !exact.contains($0) }
        let title = defs.filter {
            !$0.trigger.hasPrefix(head) && !exact.contains($0) && $0.title.localizedCaseInsensitiveContains(head)
        }
        return exact + prefix + title
    }

    // Minimal style's key-cap blocks: one per word, plus a "␣" block per space if asked.
    // An empty block at the end is where the next word goes: there when nothing is typed
    // yet, and again after each space.
    static func keyBlocks(_ text: String, showSpaces: Bool) -> [String] {
        var out: [String] = [], word = ""
        for ch in text {
            if ch != " " { word.append(ch); continue }
            if !word.isEmpty { out.append(word); word = "" }
            if showSpaces { out.append("␣") }
        }
        out.append(word) // the word being typed, or an empty block waiting for one
        return out
    }

    // Name of the argument the typed command expects, once the command and a space are in.
    var argPlaceholder: String? {
        let words = text.split(separator: " ")
        guard words.count == 1, text.hasSuffix(" "),
              let d = Command.lookup(String(words[0]), in: defs()) else { return nil }
        let own = volumeKeys().map(String.init)
        return Action(rawValue: d.id)?.argName.map { name in
            guard d.id == Action.volume.rawValue, own.count >= 2 else { return Command.spell(name, defs()) }
            let keys = own.count == 2 ? own.joined(separator: " ") : "<left> <down> <up> <right>" // "all"
            return Command.spell(name.replacingOccurrences(of: "<down> <up>", with: keys), defs())
        }
    }

    // Scroll mode: once "s " is typed, a direction key scrolls right away and is never typed,
    // so the bar stays on "s ". Returns false when the key should be typed as usual.
    func scrollKey(_ key: String) -> Bool {
        let words = text.split(separator: " ")
        guard words.count == 1, text.hasSuffix(" "),
              Command.lookup(String(words[0]), in: defs())?.id == Action.scroll.rawValue,
              let steps = Command.directionSteps(key, defs()) else { return false }
        live(.scroll(steps))
        return true
    }

    // Volume mode: after "vol " (the Mac) or "vol <app> ", a direction key raises or lowers the
    // volume right away and is never typed, like scroll mode. To name an app starting with h, j, k
    // or l, type its first letter in capitals: "vol Hulu". nil: not in volume mode; .some(nil): the Mac.
    var volumeMode: String?? {
        let s = text.drop { $0 == " " }
        guard text.hasSuffix(" "), let head = s.split(separator: " ").first,
              Command.lookup(String(head), in: defs())?.id == Action.volume.rawValue else { return nil }
        let rest = s.dropFirst(head.count).trimmingCharacters(in: .whitespaces)
        if rest.isEmpty { return .some(nil) }
        return Command.volumeParts(rest, defs()) == nil ? .some(rest) : nil // not after set, m or out
    }

    func volumeKey(_ key: String) -> Bool {
        guard let app = volumeMode, let n = volumeStep(key) else { return false }
        live(.volume(app: app, .step(n)))
        return true
    }

    // -1 quieter, 1 louder: the two keys set in Settings, else the window's down and up keys.
    // ↓ and ↑ always work. "all": left and down lower it, up and right raise it.
    func volumeStep(_ key: String) -> Int? {
        if volumeKeys() == "all" { return Command.directionSteps(key, defs()).map { Int($0.width - $0.height) } }
        let own = Array(volumeKeys())
        if own.count == 2, Command.arrowAction(key) == nil {
            return key.count == 1 ? own.firstIndex(of: Character(key)).map { $0 == 0 ? -1 : 1 } : nil
        }
        return Command.volumeSteps(key, defs())
    }

    // Tab mode: once "ts " is typed, left / right go to the previous / next tab right away
    // and are never typed, like scroll mode. Returns false when the key should be typed as usual.
    var tabMode: Bool {
        let words = text.split(separator: " ")
        return words.count == 1 && text.hasSuffix(" ") && Command.lookup(String(words[0]), in: defs())?.id == Action.tabs.rawValue
    }

    func tabKey(_ key: String) -> Bool {
        guard tabMode, let dir = Command.direction(key, in: defs()), dir == .left || dir == .right else { return false }
        live(.switchTab(next: dir == .right))
        return true
    }

    // Desktop mode: once "d " is typed, left / right go to the desktop that way right away and
    // are never typed, like tab mode. Numbers are still typed: "d 2". Set to pick first, they move
    // the highlight in the desktop strip instead, and Return goes there.
    var desktopMode: Bool {
        let words = text.split(separator: " ")
        return words.count == 1 && text.hasSuffix(" ") && Command.lookup(String(words[0]), in: defs())?.id == Action.desktop.rawValue
    }

    func desktopKey(_ key: String) -> Bool {
        guard desktopMode, Command.direction(key, in: defs()) != nil, let k = Command.desktopKey(key, defs()) else { return false }
        if desktopInstant() {
            live(.ctrlKey(k))
        } else if let from = desktopPick ?? desktops.current {
            desktopPick = min(max(from + (k == 124 ? 1 : -1), 1), max(desktops.count, 1))
        }
        return true
    }

    // Arrow mode: once "ar " is typed, each direction key presses that arrow key in the front app
    // right away and is never typed, like tab mode. "se " selects instead: a word left or right
    // per key, or the cursor's line.
    // Returns false when the key should be typed as usual.
    var arrowMode: Bool {
        let words = text.split(separator: " ")
        guard words.count == 1, text.hasSuffix(" ") else { return false }
        let id = Command.lookup(String(words[0]), in: defs())?.id
        return id == Action.arrows.rawValue || id == Action.select.rawValue
    }

    func arrowKey(_ key: String) -> Bool {
        guard arrowMode, let dir = Command.direction(key, in: defs()) else { return false }
        let select = Command.lookup(String(text.dropLast()), in: defs())?.id == Action.select.rawValue
        if select, let keys = Command.selectKeys(dir) { live(.pressKeys(keys)) } else { live(.arrow(dir)) }
        return true
    }

    // The pointer command typed with a space after it, ready for direction keys.
    var pointerMode: Action? {
        let words = text.split(separator: " ")
        guard words.count == 1, text.hasSuffix(" "),
              let a = Command.lookup(String(words[0]), in: defs()).flatMap({ Action(rawValue: $0.id) }),
              a == .pointer || a == .pointerStep else { return nil }
        return a
    }

    // Pointer mode: a direction key moves the pointer right away and is never typed. "mo " keeps
    // that half of the area left and puts the pointer in its middle; "ms " steps as set in Settings.
    // Uppercase nudges 10 points in either; Space gives "mo " the whole screen again, pointer centered.
    // Returns false when the key should be typed as usual.
    func pointerKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        if key == " ", pointerMode == .pointer {
            pointerArea = CGRect(x: 0, y: 0, width: 1, height: 1)
            if let s = screen { live(.pointerTo(CGPoint(x: s.midX, y: s.midY))) } // shows the reset
            return true
        }
        guard let mode = pointerMode, let dir = pointerDirection(lower) else { return false }
        let step: CGSize = switch dir {
        case .left: CGSize(width: -1, height: 0)
        case .right: CGSize(width: 1, height: 0)
        case .top: CGSize(width: 0, height: -1)
        default: CGSize(width: 0, height: 1)
        }
        if key != lower || mode == .pointerStep {
            let n: CGFloat = key != lower ? 10 : pointerStep()
            live(.pointerBy(CGSize(width: step.width * n, height: step.height * n)))
            return true
        }
        var a = pointerArea
        switch dir {
        case .left: a.size.width /= 2
        case .right: a.size.width /= 2; a.origin.x += a.width
        case .top: a.size.height /= 2
        default: a.size.height /= 2; a.origin.y += a.height
        }
        pointerArea = a
        if let s = screen { live(.pointerTo(CGPoint(x: s.minX + a.midX * s.width, y: s.minY + a.midY * s.height))) }
        return true
    }

    // A direction for mo / ms: an arrow, one of their own keys if set, or else a window direction key.
    func pointerDirection(_ key: String) -> Action? {
        if let a = Command.arrowAction(key) { return a }
        let own = Array(pointerKeys())
        guard own.count == 4 else { return Command.direction(key, in: defs()) }
        return key.count == 1 ? own.firstIndex(of: Character(key)).map { Action.directions[$0] } : nil
    }

    // What's typed after "cl " toward a label. An "r" or "2" in front makes it a right or double click;
    // labels never use those keys.
    var hintInput: (label: String, right: Bool, count: Int)? {
        let s = text.drop { $0 == " " }
        guard let sp = s.firstIndex(of: " "),
              Command.lookup(String(s[..<sp]), in: defs())?.id == Action.hints.rawValue else { return nil }
        var q = s[s.index(after: sp)...].filter { $0 != " " }.lowercased()
        let mod = q.first.flatMap { "r2".contains($0) ? $0 : nil }
        if mod != nil { q.removeFirst() }
        return (q, mod == "r", mod == "2" ? 2 : 1)
    }

    var visibleHints: [Hint] { hintInput.map { i in hints.filter { $0.label.hasPrefix(i.label) } } ?? [] }

    // Loads the labels when "cl " starts, clicks once a whole label is typed, and drops a key
    // that no label starts with.
    func updateHints() {
        guard let input = hintInput else { if !hints.isEmpty { hints = [] }; return }
        if hints.isEmpty {
            hints = Self.labeled(loadHints())
            if hints.isEmpty { return NSSound.beep() }
        }
        if let hit = hints.first(where: { $0.label == input.label }) {
            clickHint(.clickAt(CGPoint(x: hit.frame.midX, y: hit.frame.midY), right: input.right, count: input.count))
        } else if !input.label.isEmpty, visibleHints.isEmpty {
            NSSound.beep()
            text.removeLast()
        }
    }

    // Home-row keys, one each when they're enough, else two. Top to bottom, then left to right.
    // shortcut: two letters cap it at 81 labels; add a third when windows need more.
    static let hintKeys = "asdfghjkl".map(String.init)
    static func labeled(_ frames: [CGRect]) -> [Hint] {
        let k = hintKeys
        let labels = frames.count <= k.count ? k : k.flatMap { a in k.map { a + $0 } }
        // Rows within 8 points count as one line, so a row of buttons reads left to right.
        let sorted = frames.sorted { (Int($0.minY / 8), $0.minX) < (Int($1.minY / 8), $1.minX) }
        return zip(labels, sorted).map { Hint(label: $0, frame: $1) }
    }

    // Arrow keys type ← ↓ ↑ →, which work like h j k l.
    func typeArrow(_ arrow: String) {
        if !typeDirection(arrow) { text += arrow }
    }

    // A direction key (arrow or h j k l) right after a command that takes an argument adds the
    // space too, so "d" + h becomes "d h" and "s" + j scrolls at once. Skipped when the typed
    // text plus the key starts another trigger. Returns false when the key should be typed as usual.
    func typeDirection(_ key: String) -> Bool {
        let defs = defs()
        if scrollKey(key) || tabKey(key) || desktopKey(key) || arrowKey(key) || pointerKey(key) || volumeKey(key) || gridKey(key) { return true }
        guard let head = defs.first(where: { $0.enabled && $0.trigger == text }).flatMap({ Action(rawValue: $0.id) }) else { return false }
        // mo and ms may have their own direction keys.
        if head == .hints { return false } // "cl" + h would click label h at once
        let isDirection = head == .pointer || head == .pointerStep ? pointerDirection(key) != nil
            : head == .volume ? volumeStep(key) != nil : Command.direction(key, in: defs) != nil
        guard isDirection, head.argHint != nil, !defs.contains(where: { $0.enabled && $0.trigger.hasPrefix(text + key) }) else { return false }
        text += " "
        if !scrollKey(key), !tabKey(key), !desktopKey(key), !arrowKey(key), !pointerKey(key), !volumeKey(key) { text += key }
        return true
    }

    // Arrow glyphs sit cramped in a monospaced font; put a gap beside each arrow inside a block.
    static func spacedArrows(_ word: String) -> String {
        var out = ""
        for ch in word {
            if let last = out.last,
               Command.arrowAction(String(ch)) != nil || Command.arrowAction(String(last)) != nil {
                out.append("\u{2009}") // thin space
            }
            out.append(ch)
        }
        return out
    }

    // Esc discards what's typed first; with nothing typed, it closes the bar.
    func escape() { if text.isEmpty { cancel() } else { text = "" } }

    // Ctrl+W: drop the last word, keeping the space before it, so "re ←↑→" becomes "re ".
    func deleteWord() {
        var t = text
        while t.hasSuffix(" ") { t.removeLast() }
        while let c = t.last, c != " " { t.removeLast() }
        text = t
    }

    // While "vol" is typed: the level of the Mac's output, or of the app named so far
    // ("vol saf" before a verb is typed; not "vol se" or "vol ou", on their way to set and out).
    var volumeShown: VolumeInfo? {
        let s = text.drop { $0 == " " }
        guard let head = s.split(separator: " ").first,
              Command.lookup(String(head), in: defs())?.id == Action.volume.rawValue else { return nil }
        let rest = s.dropFirst(head.count).trimmingCharacters(in: .whitespaces)
        if let p = Command.volumeParts(rest, defs()), p.verb == "out", p.app == nil { return nil } // levels are in the list
        let app = rest.isEmpty ? nil : Command.volumeParts(rest, defs()).map(\.app)
            ?? (["set", "out"].contains { $0.hasPrefix(rest) } ? nil : rest)
        return volumeInfo(app)
    }

    // After the switch or open command and a space ("b saf", "o saf"): running or installed apps
    // whose name starts with what's typed.
    var appMatches: [AppItem]? {
        let s = text.drop { $0 == " " }
        guard let sp = s.firstIndex(of: " ") else { return nil }
        let pool: [AppItem]
        let id = Command.lookup(String(s[..<sp]), in: defs())?.id
        switch id {
        case Action.open.rawValue: pool = installed
        case Action.volume.rawValue:
            let rest = s[s.index(after: sp)...].trimmingCharacters(in: .whitespaces)
            // "vol saf": running apps whose name starts with it, without the window preview.
            guard let p = Command.volumeParts(rest, defs()) else {
                return rest.isEmpty ? nil : apps.filter { $0.name.lowercased().hasPrefix(rest.lowercased()) }
                    .map { AppItem(name: $0.name, icon: $0.icon) }
            }
            // "vol out " / "vol safari out ": the output devices.
            guard p.verb == "out" else { return nil }
            let now = currentOutput(p.app)
            return outputs.filter { p.rest.isEmpty || $0.name.lowercased().hasPrefix(p.rest.lowercased()) }
                .map { var d = $0; d.current = d.name == now; return d }
        default: return nil
        }
        let q = s[s.index(after: sp)...].trimmingCharacters(in: .whitespaces).lowercased()
        return pool.filter { q.isEmpty || $0.name.lowercased().hasPrefix(q) }
    }

    // After the switch command and a space ("b ", "b saf"): every window on every desktop whose
    // app name starts with what's typed, or whose title has it.
    var windowMatches: [WindowItem]? {
        let s = text.drop { $0 == " " }
        guard let sp = s.firstIndex(of: " "),
              Command.lookup(String(s[..<sp]), in: defs())?.id == Action.focus.rawValue else { return nil }
        let q = s[s.index(after: sp)...].trimmingCharacters(in: .whitespaces).lowercased()
        if Command.direction(q, in: defs()) != nil { return nil } // "b h": the nearest window that way
        return windows.filter { q.isEmpty || $0.app.lowercased().hasPrefix(q) || $0.title.lowercased().contains(q) }
    }

    // Where the highlight starts: on the previous window once "b " is typed, before any name;
    // otherwise the top.
    var initialSelection: Int {
        guard text.split(separator: " ").count == 1, let list = windowMatches else { return 0 }
        return list.firstIndex { $0.id == previousWindow } ?? 0
    }

    static let gridColumns = 3
    // The window grid's rows, as indexes into the list: three across, each group on new rows.
    static func gridRows(_ list: [WindowItem]) -> [[Int]] {
        var rows: [[Int]] = []
        for i in list.indices {
            if i == 0 || list[i].group != list[i - 1].group || rows[rows.count - 1].count == gridColumns {
                rows.append([i])
            } else {
                rows[rows.count - 1].append(i)
            }
        }
        return rows
    }

    // In the window grid, direction keys move the highlight and are never typed: arrows always,
    // h j k l only before a name is typed ("b " + l, while "b" + l is still the nearest window).
    func gridKey(_ key: String) -> Bool {
        guard let list = windowMatches, !list.isEmpty, let dir = Command.direction(key, in: defs()),
              Command.arrowAction(key) != nil || text.split(separator: " ").count == 1 else { return false }
        let rows = Self.gridRows(list)
        let r = rows.firstIndex { $0.contains(selected) } ?? 0, c = rows[r].firstIndex(of: selected) ?? 0
        switch dir {
        case .left: selected = max(selected - 1, 0)
        case .right: selected = min(selected + 1, list.count - 1)
        case .top: if r > 0 { selected = rows[r - 1][min(c, rows[r - 1].count - 1)] }
        default: if r + 1 < rows.count { selected = rows[r + 1][min(c, rows[r + 1].count - 1)] }
        }
        return true
    }

    func move(_ by: Int) {
        let n = windowMatches?.count ?? appMatches?.count ?? matches.count
        if n > 0 { selected = (selected + by + n) % n }
    }

    // Enter: with arguments typed, run the text as-is. Otherwise act on the selected row:
    // commands that need an argument get their trigger filled in, the rest run.
    // Shift+Enter does the same but keeps going: the bar comes back for another command.
    func enter(continuing: Bool = false) {
        let run = continuing ? submitContinuing : submit
        // "vol saf": Return fills in the highlighted app, ready for h j k l, set, m or out.
        if let list = appMatches, list.indices.contains(selected), let head = text.split(separator: " ").first,
           Command.lookup(String(head), in: defs())?.id == Action.volume.rawValue, !text.contains(" out") {
            let filled = head + " " + list[selected].name + " "
            if text != filled { text = filled; return }
        }
        // Return in tab, arrow or volume mode just closes the bar: the keys already did their work.
        if desktopMode, let n = desktopPick { return run(text + String(n)) } // picked with left / right
        if !continuing, tabMode || desktopMode || arrowMode || volumeMode != nil { return cancel() }
        defer { pointerArea = CGRect(x: 0, y: 0, width: 1, height: 1) } // the next "mo " starts from the whole screen
        // Picking from the window grid brings that window forward.
        if let list = windowMatches, list.indices.contains(selected) { return pickWindow(list[selected]) }
        // Picking from the app list switches to the highlighted app.
        if let list = appMatches, list.indices.contains(selected), let head = text.split(separator: " ").first {
            // "vol [app] out": everything up to "out" stays.
            if Command.lookup(String(head), in: defs())?.id == Action.volume.rawValue,
               let out = text.range(of: " out", options: .backwards) {
                return run(text[..<out.upperBound] + " " + list[selected].name)
            }
            return run(head + " " + list[selected].name)
        }
        // Shift+Enter with nothing it can run finishes it: the bar stays up, empty, for the next
        // command, so Esc isn't needed. A mode with nothing typed ("s ", "re ", "cl " or a half-typed
        // label) ends quietly; a slip like "ar i" or "d 0" goes through to beep first.
        let words = text.split(separator: " ")
        if continuing, text.contains(" "), Command.parse(text, defs()) == nil,
           let head = words.first.flatMap({ Command.lookup(String($0), in: defs()) }) {
            if words.count > 1, head.id != Action.hints.rawValue { run(text) }
            text = ""
            return
        }
        let rows = matches
        guard !text.contains(" "), rows.indices.contains(selected) else { return run(text) }
        let d = rows[selected]
        if Action(rawValue: d.id)?.argRequired == true { text = d.trigger + " " } else { run(d.trigger) }
    }
}

struct PaletteView: View {
    @ObservedObject var model: Palette
    @ObservedObject var store = Store.shared
    @FocusState private var focused: Bool
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Movement is dropped under Reduce Motion; fades stay, since they still explain the change.
    func motion(_ duration: Double) -> Animation? { reduceMotion ? nil : .uiEaseOut(duration) }

    var body: some View {
        let minimal = store.style == .minimal, island = store.style == .island, glow = store.style == .glow
        // The command bar style and the island always sit at the top; glow at the bottom, by its light;
        // minimal uses the chosen position.
        let position = minimal ? store.position : glow ? .bottom : .top
        let alignment: Alignment = switch position {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        }
        GeometryReader { g in
            VStack(spacing: 10) {
                if island {
                    // The hidden field still receives the typing; behind the pill, so the stack's
                    // spacing doesn't push the pill off the top edge.
                    islandPill.background(field.frame(width: 1, height: 1).opacity(0))
                        // Full width, so the pill stays centered under the notch when the desktop
                        // strip or list below widens the stack; only its own width animates.
                        .frame(maxWidth: .infinity)
                    content
                } else if minimal || glow {
                    // Still receives the typing; only the letter squares below show it.
                    field.frame(width: 1, height: 1).opacity(0)
                    if position == .top { keys }
                    content
                    if position != .top, !glow || store.glowKeys { keys }
                } else {
                    field
                        .padding(.horizontal, 24)
                        .frame(height: 60)
                        .glass(Capsule())
                    content
                }
            }
            // Entrance: grows from the edge it's anchored to; Reduce Motion keeps only the fade.
            // Placed inside the animation, so when the desktop strip or list resizes the stack, its
            // position animates with its contents; outside, the stack moved at once while the key
            // caps animated from their old spot, and jumped.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            // Desktop thumbnails fade in when a desktop command is typed.
            .animation(motion(0.18) ?? .linear(duration: 0.1), value: model.desktopCommand?.id)
            .opacity(model.visible ? 1 : 0)
            .scaleEffect(model.visible || reduceMotion ? 1 : 0.97, anchor: alignment.unitPoint)
            .padding(.horizontal, 20).padding(.bottom, 20) // room for the shadow
            .padding(.top, island ? 0 : 20)
            .padding(.top, position == .top && !island ? g.size.height * 0.15 : 0)
            .padding(.bottom, position == .bottom ? g.size.height * 0.08 : 0)
            .frame(width: g.size.width, height: g.size.height, alignment: alignment)
        }
        // The island sits in the strip beside the notch, which SwiftUI otherwise keeps clear.
        .ignoresSafeArea(edges: island ? .top : [])
        .onChange(of: model.focusToken) { focused = true }
    }

    var field: some View {
        TextField("Type a command", text: $model.text)
            .textFieldStyle(.plain)
            .font(.system(size: 22))
            .focused($focused)
            .onSubmit { model.enter() }
            // Repeats too, so holding a key keeps scrolling or moving through the list.
            .onKeyPress(phases: [.down, .repeat]) { press in
                switch press.key {
                case .leftArrow: model.typeArrow("←")
                case .downArrow: model.typeArrow("↓")
                case .upArrow: model.typeArrow("↑")
                case .rightArrow: model.typeArrow("→")
                // The list highlight moves with Tab / Shift+Tab or Vim's Ctrl+N / Ctrl+P.
                case .tab: model.move(press.modifiers.contains(.shift) ? -1 : 1)
                case KeyEquivalent("\u{19}"): model.move(-1) // Shift+Tab can arrive as backtab
                case "n" where press.modifiers.contains(.control): model.move(1)
                case "p" where press.modifiers.contains(.control): model.move(-1)
                case .return where press.modifiers.contains(.shift): model.enter(continuing: true)
                case .escape: model.escape()
                case _ where press.modifiers.subtracting(.shift).isEmpty && model.pointerKey(press.characters): break // H J K L nudge
                case _ where press.modifiers.isEmpty && model.typeDirection(press.characters): break
                case "u" where press.modifiers.contains(.control): model.text = "" // discard, like a shell
                case "w" where press.modifiers.contains(.control): model.deleteWord()
                default: return .ignored
                }
                return .handled
            }
    }

    @ViewBuilder var content: some View {
        let rows = model.matches
        if let cmd = model.desktopCommand, model.desktops.count > 0 {
            desktopStrip(cmd)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
        if let v = model.volumeShown {
            volumeMeter(v)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
        if let wins = model.windowMatches {
            if !wins.isEmpty {
                windowGrid(wins)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        } else if let apps = model.appMatches {
            if !apps.isEmpty {
                // Up to 8 rows tall; scrolls to keep the highlight in view.
                ScrollViewReader { scroll in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(apps.enumerated()), id: \.element.name) { i, app in
                                appRow(app, selected: i == model.selected)
                                    .id(i)
                                    .onTapGesture { model.selected = i; model.enter() }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .frame(height: CGFloat(min(apps.count, 8)) * 42 - 2)
                    .onChange(of: model.selected) { scroll.scrollTo(model.selected) }
                }
                .padding(8)
                .glass(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .animation(motion(0.18) ?? .linear(duration: 0.1), value: apps.map(\.name))
                .animation(motion(0.15), value: model.selected)
            }
        } else if store.showList, !rows.isEmpty {
            list(rows)
            .padding(8)
            .glass(RoundedRectangle(cornerRadius: 26, style: .continuous))
            // Filtering: rows fade and the panel resizes instead of jumping.
            .animation(motion(0.18) ?? .linear(duration: 0.1), value: rows.map(\.id))
            .animation(motion(0.15), value: model.selected)
        }
    }

    // Dynamic Island style: a black island flush with the top of the screen, as tall as the menu
    // bar (or the notch) plus a line for what's typed, and at least as wide as the notch.
    // Depth without breaking the black: concave shoulders where it meets the bezel, a lit lower
    // edge fading out toward the top, and a soft shadow so it floats over what's under it.
    // It grows out of the notch on open and with the text as you type, on a light spring;
    // Reduce Motion keeps only the fade.
    var islandPill: some View {
        let screen = NSScreen.main
        let top = screen.map { max($0.safeAreaInsets.top, $0.frame.maxY - $0.visibleFrame.maxY) } ?? 32
        let notch = screen.flatMap { s in
            s.auxiliaryTopLeftArea.flatMap { l in s.auxiliaryTopRightArea.map { r in s.frame.width - l.width - r.width } }
        } ?? 180
        let hint = model.argPlaceholder
        // The command being typed: its trigger once a space is in, else the highlighted match.
        let head = model.text.split(separator: " ").first.flatMap { model.text.contains(" ") ? Command.lookup(String($0), in: model.defs()) : nil }
            ?? (model.text.isEmpty || !model.matches.indices.contains(model.selected) ? nil : model.matches[model.selected])
        let shape = IslandShape()
        let spring: Animation? = reduceMotion ? nil : .spring(duration: 0.38, bounce: 0.15)
        return HStack(spacing: 10) {
            Image(systemName: head?.icon ?? "command")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(head == nil ? 0.5 : 0.95))
                .frame(width: 20)
                .contentTransition(.symbolEffect(.replace))
            if model.text.isEmpty {
                Text("Type a command").foregroundStyle(.white.opacity(0.45))
            } else {
                Text(Palette.spacedArrows(model.text))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            // What it is, or what it wants next: muted, like a Live Activity's trailing detail.
            // No spacer: the whole line stays centered under the notch.
            if let detail = hint.map({ $0.replacingOccurrences(of: "\n", with: " · ") }) ?? head?.title {
                Text(detail)
                    .padding(.leading, 4)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .transition(.opacity)
            }
        }
        .font(.system(size: 15, weight: .medium))
        .lineLimit(1)
        .padding(.horizontal, 18 + IslandShape.shoulder)
        .frame(minWidth: notch + 60, minHeight: 40)
        .fixedSize()
        .padding(.top, top)
        .padding(.bottom, 8)
        .background {
            shape.fill(.black)
                .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
                // Light catching the lower edge; clear at the top, so it melts into the bezel.
                .overlay(shape.stroke(LinearGradient(colors: [.clear, .white.opacity(0.14)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1))
        }
        .environment(\.colorScheme, .dark)
        // Out of the notch: narrow and short at first, anchored to the top edge.
        .scaleEffect(x: model.visible || reduceMotion ? 1 : 0.55, y: model.visible || reduceMotion ? 1 : 0.6, anchor: .top)
        .animation(spring, value: model.visible)
        .animation(spring, value: model.text)
        .animation(spring, value: head?.id)
    }

    // Minimal style: one key-cap block per typed word, so "o Safari" shows [o] [Safari],
    // plus an empty block for the next word. New blocks pop in.
    // shortcut: long input runs past the panel edge; wrap if that becomes a problem.
    var keys: some View {
        var blocks = Palette.keyBlocks(model.text, showSpaces: store.showSpaces)
        // While a strip, grid or list shows what to pick, the empty block waiting for the next
        // word says nothing; it stays when it holds the options.
        let choosing = model.text.contains(" ") && (model.windowMatches != nil || model.appMatches?.isEmpty == false
            || model.desktopCommand != nil && model.desktops.count > 0)
        if choosing, blocks.count > 1, blocks.last == "", !(store.showHints && model.argPlaceholder != nil) { blocks.removeLast() }
        return HStack(spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, word in
                let hint = store.showHints && i == blocks.count - 1 ? model.argPlaceholder : nil // off: an empty cap
                let stacked = store.hintsVertical && hint?.contains("\n") == true
                Text(hint.map { stacked ? $0 : $0.replacingOccurrences(of: "\n", with: " · ") } ?? Palette.spacedArrows(word))
                    .font(hint == nil ? .system(size: 22, weight: .medium, design: .monospaced) : .system(size: stacked ? 14 : 17))
                    .foregroundStyle(hint == nil ? .primary : .secondary)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, stacked ? 10 : 0)
                    .frame(minWidth: 44, minHeight: 44)
                    .glass(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
            }
        }
        // Typed many times a day, so quick and without bounce.
        .animation(motion(0.15) ?? .linear(duration: 0.1), value: blocks)
    }

    // Mission Control-style thumbnails: target gets the accent border, current a faint one.
    // Click a thumbnail to go/move there. With desktop previews off, numbered boxes instead,
    // so where you are and how many there are still show.
    func desktopStrip(_ cmd: CommandDef) -> some View {
        let d = model.desktops
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return HStack(alignment: .top, spacing: 14) {
            ForEach(Array(d.ids.enumerated()), id: \.element) { i, id in
                let n = i + 1
                let isTarget = n == model.desktopTarget
                let border = shape.strokeBorder(isTarget ? Color.accentColor : Color.white.opacity(n == d.current ? 0.6 : 0.15),
                                                lineWidth: isTarget ? 3 : 1)
                Group {
                    if !store.desktopPreviews {
                        Text("\(n)")
                            .font(.system(size: 15, weight: n == d.current ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(n == d.current || isTarget ? .primary : .secondary)
                            .frame(maxWidth: 56).frame(height: 36)
                            .background(shape.fill(Color.primary.opacity(n == d.current ? 0.14 : 0.05)))
                            .overlay(border)
                            .accessibilityLabel("Desktop \(n)" + (n == d.current ? ", current" : ""))
                    } else {
                        VStack(spacing: 6) {
                            Color.clear
                                .aspectRatio(16 / 10, contentMode: .fit)
                                .overlay { thumbnail(id) }
                                .clipShape(shape)
                                .overlay(border)
                            Text("Desktop \(n)")
                                .font(.system(size: 12, weight: n == d.current ? .semibold : .regular))
                                .foregroundStyle(n == d.current ? .primary : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: 160)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.submit("\(cmd.trigger) \(n)") }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(motion(0.15) ?? .linear(duration: 0.1), value: model.desktopTarget)
    }

    @ViewBuilder func thumbnail(_ id: Int) -> some View {
        if let img = model.thumbs[id] ?? model.wallpaper {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            Color.primary.opacity(0.08)
        }
    }

    // The list in the layout picked in Settings. Every layout keeps the order of `matches`,
    // so Tab / Ctrl+N walk it the way it reads.
    @ViewBuilder func list(_ rows: [CommandDef]) -> some View {
        let items = Array(rows.enumerated())
        switch store.listStyle {
        case .grid:
            // As tall as it needs while it fits on screen; past that it scrolls, following the highlight.
            ViewThatFits(in: .vertical) {
                grid(items)
                ScrollViewReader { scroll in
                    ScrollView { grid(items) }
                        .scrollIndicators(.never)
                        .onChange(of: model.selected) {
                            if rows.indices.contains(model.selected) { scroll.scrollTo(rows[model.selected].id) }
                        }
                }
            }
        case .grouped:
            // Section headers where the group changes; capped height, scrolls to the highlight.
            let headerAt = Set(items.filter { i, d in
                i == 0 || rows[i - 1].group != d.group
            }.map(\.offset))
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(items, id: \.element.id) { i, d in
                            if headerAt.contains(i) {
                                sectionHeader(d.group, first: i == 0)
                            }
                            tappableRow(i, d, height: 34).id(d.id)
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: min(CGFloat(items.count) * 34 + CGFloat(headerAt.count) * 28, 440))
                .onChange(of: model.selected) {
                    if rows.indices.contains(model.selected) { scroll.scrollTo(rows[model.selected].id) }
                }
            }
        }
    }

    // Runs of window commands become tile grids; everything else stays a row.
    func grid(_ items: [(offset: Int, element: CommandDef)]) -> some View {
        let runs = items.reduce(into: [[(offset: Int, element: CommandDef)]]()) { runs, item in
            let tile = Action(rawValue: item.element.id)?.isWindow == true
            if let last = runs.last?.last, (Action(rawValue: last.element.id)?.isWindow == true) == tile {
                runs[runs.count - 1].append(item)
            } else { runs.append([item]) }
        }
        return VStack(spacing: 2) {
            ForEach(runs, id: \.first!.element.id) { run in
                if Action(rawValue: run[0].element.id)?.isWindow == true {
                    sectionHeader("Windows", first: run[0].offset == 0)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(60), spacing: 6), count: 8), spacing: 6) {
                        ForEach(run, id: \.element.id) { i, d in tile(i, d).id(d.id) }
                    }
                    .padding(.bottom, 4)
                    // Tiles have no titles; name the highlighted one, with what it does.
                    Group {
                        if let sel = run.first(where: { $0.offset == model.selected }) {
                            Text(sel.element.title)
                        } else {
                            Text("Use Tab to see each name")
                        }
                    }
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(height: 18)
                    .padding(.bottom, 6)
                } else {
                    ForEach(run, id: \.element.id) { i, d in tappableRow(i, d, height: 40).id(d.id) }
                }
            }
        }
    }

    // "b ": every window as a picture, under its desktop. Up to about three rows tall; scrolls
    // to keep the highlight in view. Pictures arrive as they're taken; the app icon until then
    // (or without Screen Recording).
    func windowGrid(_ wins: [WindowItem]) -> some View {
        let rows = Palette.gridRows(wins)
        let starts = rows.indices.filter { $0 == 0 || wins[rows[$0][0]].group != wins[rows[$0 - 1][0]].group }
        return ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(rows.indices, id: \.self) { r in
                        if starts.contains(r) { sectionHeader(wins[rows[r][0]].group, first: r == 0) }
                        HStack(spacing: 4) {
                            ForEach(rows[r], id: \.self) { i in
                                windowTile(wins[i], selected: i == model.selected)
                                    .id(i)
                                    .onTapGesture { model.selected = i; model.enter() }
                            }
                        }
                        .frame(maxWidth: .infinity) // a short row sits in the middle
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: min(CGFloat(rows.count) * 146 + CGFloat(starts.count) * 26, 480))
            .onChange(of: model.selected) { scroll.scrollTo(model.selected) }
        }
        .padding(8)
        .glass(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .animation(motion(0.18) ?? .linear(duration: 0.1), value: wins.map(\.id))
        .animation(motion(0.15), value: model.selected)
        .task(id: wins.map(\.id)) { if store.windowPreviews { model.loadShots(wins.map(\.id).filter { $0 != 0 && model.windowShots[$0] == nil }) } }
    }

    func windowTile(_ w: WindowItem, selected: Bool) -> some View {
        let shot = store.windowPreviews ? model.windowShots[w.id] : nil // off: the app icon
        let note = w.hidden ? "Hidden" : w.id == 0 ? "No open window" : w.title.isEmpty ? "" : w.app
        return VStack(spacing: 2) {
            ZStack(alignment: .bottomLeading) {
                if let shot {
                    Image(nsImage: shot).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let icon = w.icon { Image(nsImage: icon).resizable().frame(width: 24, height: 24) }
                } else if let icon = w.icon {
                    Image(nsImage: icon).resizable().frame(width: 48, height: 48)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 90)
            .padding(.bottom, 4)
            Text(w.title.isEmpty ? w.app : w.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            Text(note.isEmpty ? " " : note).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(8)
        .frame(width: 176, height: 142)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.1))
                    .matchedGeometryEffect(id: "selection", in: selection)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([w.title.isEmpty ? w.app : w.title, note, w.group].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    func volumeMeter(_ v: VolumeInfo) -> some View {
        HStack(spacing: 14) {
            Image(systemName: v.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 18)).frame(width: 26)
            VStack(alignment: .leading, spacing: 6) {
                Text(v.title).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.12))
                        Capsule().fill(Color.primary.opacity(v.muted ? 0.3 : 0.8))
                            .frame(width: g.size.width * CGFloat(v.level ?? 0))
                    }
                }
                .frame(height: 6)
            }
            Text(v.level == nil ? "No control" : v.muted ? "Muted" : Volume.percent(v.level!))
                .font(.system(size: 15).monospacedDigit())
                .frame(minWidth: 48, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .frame(height: 64)
        .glass(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .animation(motion(0.15), value: v)
        .accessibilityElement(children: .combine)
    }

    func appRow(_ app: AppItem, selected: Bool) -> some View {
        HStack(spacing: 14) {
            if let symbol = app.symbol {
                // An output device: its kind in a circle, filled blue for the one in use, and its volume.
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(app.current ? Color.white : Color.primary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(app.current ? Color.accentColor : Color.primary.opacity(0.12)))
            } else if let icon = app.icon ?? app.path.map(NSWorkspace.shared.icon(forFile:)) {
                Image(nsImage: icon).resizable().frame(width: 26, height: 26)
            }
            Text(app.name).font(.system(size: 15)).lineLimit(1)
            Spacer()
            if app.symbol != nil {
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 12)).foregroundStyle(.secondary)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(Color.accentColor).frame(width: 150 * CGFloat(app.level ?? 0))
                }
                .frame(width: 150, height: 5)
                Text(app.level.map(Volume.percent) ?? "–")
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.name)
        .accessibilityValue(app.symbol == nil ? "" : [app.current ? "in use" : nil, app.level.map(Volume.percent)].compactMap { $0 }.joined(separator: ", "))
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.1))
                    .matchedGeometryEffect(id: "selection", in: selection)
            }
        }
        .contentShape(Rectangle())
    }

    // Group name above a run of rows or tiles; the first one sits closer to the top.
    func sectionHeader(_ title: String, first: Bool) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, first ? 4 : 10).padding(.bottom, 4)
    }

    func tappableRow(_ i: Int, _ d: CommandDef, height: CGFloat) -> some View {
        row(d, selected: i == model.selected, height: height)
            .onTapGesture { model.selected = i; model.enter() }
            .transition(.opacity)
    }

    // Grid style: icon with the trigger under it; the full name shows below the grid when highlighted.
    func tile(_ i: Int, _ d: CommandDef) -> some View {
        VStack(spacing: 6) {
            Image(systemName: d.icon).font(.system(size: 18))
            KeyCap(d.trigger)
        }
        .frame(width: 60, height: 62)
        .background {
            if i == model.selected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.1))
                    .matchedGeometryEffect(id: "selection", in: selection)
            }
        }
        .contentShape(Rectangle())
        .help(d.title)
        .onTapGesture { model.selected = i; model.enter() }
        .transition(.opacity)
    }

    func row(_ d: CommandDef, selected: Bool, height: CGFloat = 40) -> some View {
        let a = Action(rawValue: d.id)
        return HStack(spacing: 16) {
            Image(systemName: d.icon)
                .font(.system(size: 17))
                .frame(width: 24)
            Text(d.title).font(.system(size: 15))
            Spacer()
            // What to type: the trigger as a key, then what goes after it.
            HStack(spacing: 6) {
                KeyCap(d.trigger)
                if let arg = a?.argName {
                    // A list row stays one line; the options stack only in the key cap.
                    Text(Command.spell(arg.replacingOccurrences(of: "\n", with: " · "), model.defs()))
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: height)
        .background {
            // One highlight that slides between rows, so the eye follows the selection.
            if selected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.1))
                    .matchedGeometryEffect(id: "selection", in: selection)
            }
        }
        .contentShape(Rectangle())
    }
}

// Full-screen, click-through layer under the bar: a translucent box where the window will go,
// like macOS's own tiling preview.
// Glow style: colored light along the full bottom edge of the screen, in its own click-through
// panel. The blooms drift up and down like a slow equalizer; each keystroke kicks them up and
// they settle back, like a volume meter. Reduce Motion keeps a still glow.
struct EdgeGlow: View {
    @ObservedObject var model: Palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var kick = Date.distantPast

    static let colors: [Color] = [.green, .cyan, .blue, .purple, .pink, .orange, .yellow]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !model.visible)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let pulse = reduceMotion ? 0 : exp(-max(0, ctx.date.timeIntervalSince(kick)) * 3)
            let seed = kick.timeIntervalSinceReferenceDate // a different shape per keystroke
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Self.colors.indices, id: \.self) { i in
                        let d = Double(i)
                        let idle = reduceMotion ? 1 : 1 + 0.3 * sin(t * 1.3 + d * 1.7)
                        let h = 80 * idle + 170 * pulse * (0.6 + 0.4 * sin(seed * 7 + d * 2.3))
                        // Centered on the edge so only the upper half shows.
                        Ellipse().fill(Self.colors[i].opacity(0.5))
                            .scaleEffect(x: 1.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: h)
                            .offset(y: h / 2)
                    }
                }
                .blur(radius: 24)
                // The lit seam itself.
                LinearGradient(colors: Self.colors, startPoint: .leading, endPoint: .trailing)
                    .frame(height: 2)
                    .opacity(0.7 + 0.3 * pulse)
                    .blendMode(.plusLighter)
            }
            .opacity(model.text.isEmpty ? 0.6 + 0.4 * pulse : 0.85 + 0.15 * pulse)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .clipped()
        .opacity(model.visible ? 1 : 0)
        .offset(y: model.visible || reduceMotion ? 0 : 30)
        .animation(reduceMotion ? nil : .uiEaseOut(0.3), value: model.visible)
        .onChange(of: model.text) { kick = .now }
    }
}

struct LayoutPreview: View {
    @ObservedObject var model: Palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            if let r = model.layoutPreview {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 2))
                    .frame(width: g.size.width * r.width - 16, height: g.size.height * r.height - 16)
                    .position(x: g.size.width * r.midX, y: g.size.height * r.midY)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            }
            if let s = model.screen {
                let typed = model.hintInput?.label.count ?? 0
                ForEach(model.visibleHints, id: \.label) { h in
                    // Letters already typed go faint, so the ones still to type stand out.
                    (Text(h.label.prefix(typed).uppercased()).foregroundColor(.black.opacity(0.4))
                        + Text(h.label.dropFirst(typed).uppercased()).foregroundColor(.black))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color(red: 1, green: 0.84, blue: 0.2), in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.35)))
                        .fixedSize()
                        .position(x: h.frame.minX - s.minX + 10, y: h.frame.minY - s.minY + 8)
                }
            }
        }
        // Switching h to l slides the box across (spatial: shows where the window goes).
        .animation(reduceMotion ? .linear(duration: 0.1) : .spring(duration: 0.25, bounce: 0), value: model.layoutPreview)
    }
}

extension Alignment {
    var unitPoint: UnitPoint {
        switch self {
        case .top: .top
        case .bottom: .bottom
        default: .center
        }
    }
}

extension Animation {
    // Strong ease-out for UI state changes (fast start, soft landing).
    static func uiEaseOut(_ duration: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: duration) }
}

extension View {
    @ViewBuilder func glass<S: Shape>(_ shape: S) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape).shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
    }
}

// The island's outline: flush with the top edge, flaring out at the top into small concave
// shoulders (as the notch meets the bezel), with round bottom corners.
struct IslandShape: Shape {
    static let shoulder: CGFloat = 10
    var radius: CGFloat = 22

    func path(in r: CGRect) -> Path {
        let e = Self.shoulder
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.minX + e, y: r.minY), tangent2End: CGPoint(x: r.minX + e, y: r.minY + e), radius: e)
        p.addArc(tangent1End: CGPoint(x: r.minX + e, y: r.maxY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: radius)
        p.addArc(tangent1End: CGPoint(x: r.maxX - e, y: r.maxY), tangent2End: CGPoint(x: r.maxX - e, y: r.minY), radius: radius)
        p.addArc(tangent1End: CGPoint(x: r.maxX - e, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: e)
        p.closeSubpath()
        return p
    }
}
