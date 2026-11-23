import Carbon
import SwiftUI

enum Action: String, CaseIterable {
    case open, focus, desktop, move, tab, newTab, closeTab, nextTab, prevTab, tabs, back, forward, left, right, top, bottom, full, center
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds, topLeft, topRight, bottomLeft, bottomRight
    case grow, shrink, resize
    case scroll, arrows
    case copy, cut, copyWord, cutWord, paste, undo, redo, selectAll, select, deselect, lineStart, lineEnd
    case pointer, pointerStep, hints
    case volume, playPause, nextTrack, prevTrack, skipForward, skipBack
    case settings

    // Left, down, up, right: the direction keys are these commands' triggers.
    static let directions: [Action] = [.left, .bottom, .top, .right]

    var defaultTrigger: String {
        switch self {
        case .open: "o"
        case .focus: "b"
        case .desktop: "d"
        case .move: "m"
        case .tab: "t"
        case .newTab: "nt"
        case .closeTab: "ct"
        case .nextTab: "tn"
        case .prevTab: "tp"
        case .tabs: "ts"
        case .back: "bk"
        case .forward: "fw"
        case .left: "h"
        case .right: "l"
        case .top: "k"
        case .bottom: "j"
        case .full: "f"
        case .center: "c"
        case .leftThird: "h3"
        case .centerThird: "c3"
        case .rightThird: "l3"
        case .leftTwoThirds: "h23"
        case .rightTwoThirds: "l23"
        case .topLeft: "hk"
        case .topRight: "lk"
        case .bottomLeft: "hj"
        case .bottomRight: "lj"
        case .grow: "+"
        case .shrink: "-"
        case .resize: "re"
        case .scroll: "s"
        case .arrows: "ar"
        case .copy: "cp"
        case .copyWord: "cpw"
        case .lineStart: "ls"
        case .deselect: "ds"
        case .lineEnd: "le"
        case .cutWord: "cuw"
        case .cut: "cu"
        case .paste: "pa"
        case .undo: "u"
        case .redo: "rd"
        case .selectAll: "sa"
        case .select: "se"
        case .pointer: "mo"
        case .pointerStep: "ms"
        case .hints: "cl"
        case .volume: "vol"
        case .playPause: "pp"
        case .nextTrack: "nx"
        case .prevTrack: "pv"
        case .skipForward: "ff"
        case .skipBack: "rw"
        case .settings: "set"
        }
    }

    var title: String {
        switch self {
        case .open: "Open App"
        case .focus: "Switch to App"
        case .desktop: "Go to Desktop"
        case .move: "Move Window to Desktop"
        case .tab: "Move Tab to New Window"
        case .newTab: "New Tab"
        case .closeTab: "Close Tab"
        case .nextTab: "Next Tab"
        case .prevTab: "Previous Tab"
        case .tabs: "Switch Tabs"
        case .back: "Back"
        case .forward: "Forward"
        case .left: "Left Half"
        case .right: "Right Half"
        case .top: "Top Half"
        case .bottom: "Bottom Half"
        case .full: "Fill Screen"
        case .center: "Center"
        case .leftThird: "Left Third"
        case .centerThird: "Center Third"
        case .rightThird: "Right Third"
        case .leftTwoThirds: "Left Two Thirds"
        case .rightTwoThirds: "Right Two Thirds"
        case .topLeft: "Top Left Quarter"
        case .topRight: "Top Right Quarter"
        case .bottomLeft: "Bottom Left Quarter"
        case .bottomRight: "Bottom Right Quarter"
        case .grow: "Make Bigger"
        case .shrink: "Make Smaller"
        case .resize: "Resize by Direction"
        case .scroll: "Scroll"
        case .arrows: "Arrow Keys"
        case .copy: "Copy"
        case .copyWord: "Copy Whole Word"
        case .lineStart: "Start of Line"
        case .deselect: "Deselect"
        case .lineEnd: "End of Line"
        case .cutWord: "Cut Whole Word"
        case .cut: "Cut"
        case .paste: "Paste"
        case .undo: "Undo"
        case .redo: "Redo"
        case .selectAll: "Select All"
        case .select: "Select"
        case .pointer: "Pointer by Halves"
        case .pointerStep: "Pointer by Steps"
        case .hints: "Click by Label"
        case .volume: "Volume"
        case .playPause: "Play / Pause"
        case .nextTrack: "Next Track"
        case .prevTrack: "Previous Track"
        case .skipForward: "Forward 10s"
        case .skipBack: "Back 10s"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .open: "arrow.up.forward.app"
        case .focus: "macwindow.on.rectangle"
        case .desktop: "rectangle.3.group"
        case .move: "rectangle.portrait.and.arrow.right"
        case .tab: "macwindow.badge.plus"
        case .newTab: "plus.square"
        case .closeTab: "xmark.square"
        case .nextTab: "arrow.right.square"
        case .prevTab: "arrow.left.square"
        case .tabs: "arrow.left.arrow.right.square"
        case .back: "chevron.backward"
        case .forward: "chevron.forward"
        case .left: "rectangle.lefthalf.filled"
        case .right: "rectangle.righthalf.filled"
        case .top: "rectangle.tophalf.filled"
        case .bottom: "rectangle.bottomhalf.filled"
        case .full: "rectangle.fill"
        case .center: "rectangle.center.inset.filled"
        case .leftThird: "rectangle.leadingthird.inset.filled"
        case .centerThird: "rectangle.split.3x1"
        case .rightThird: "rectangle.trailingthird.inset.filled"
        case .leftTwoThirds: "rectangle.leadinghalf.inset.filled" // no two-thirds symbol
        case .rightTwoThirds: "rectangle.trailinghalf.inset.filled"
        case .topLeft: "rectangle.inset.topleft.filled"
        case .topRight: "rectangle.inset.topright.filled"
        case .bottomLeft: "rectangle.inset.bottomleft.filled"
        case .bottomRight: "rectangle.inset.bottomright.filled"
        case .grow: "arrow.up.left.and.arrow.down.right"
        case .shrink: "arrow.down.right.and.arrow.up.left"
        case .resize: "arrow.up.and.down.and.arrow.left.and.right"
        case .scroll: "scroll"
        case .arrows: "arrowkeys"
        case .copy: "doc.on.doc"
        case .copyWord: "doc.on.doc.fill"
        case .lineStart: "arrow.left.to.line"
        case .deselect: "rectangle.dashed"
        case .lineEnd: "arrow.right.to.line"
        case .cutWord: "scissors.circle"
        case .cut: "scissors"
        case .paste: "doc.on.clipboard"
        case .undo: "arrow.uturn.backward"
        case .redo: "arrow.uturn.forward"
        case .selectAll: "selection.pin.in.out"
        case .select: "character.cursor.ibeam"
        case .pointer: "cursorarrow.rays"
        case .pointerStep: "cursorarrow.motionlines"
        case .hints: "cursorarrow.click"
        case .volume: "speaker.wave.2"
        case .playPause: "playpause"
        case .nextTrack: "forward.end"
        case .prevTrack: "backward.end"
        case .skipForward: "goforward.10"
        case .skipBack: "gobackward.10"
        case .settings: "gearshape"
        }
    }

    // Window placement and sizing: shown as tiles in the grid list.
    var isWindow: Bool { ["Halves", "Thirds", "Quarters", "Fill & Center", "Resize"].contains(group) }

    // Section the command is listed under in Settings.
    var group: String {
        switch self {
        case .open, .focus: "Apps"
        case .desktop, .move, .tab, .newTab, .closeTab, .nextTab, .prevTab, .tabs, .back, .forward: "Desktops & Tabs"
        case .left, .right, .top, .bottom: "Halves"
        case .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds: "Thirds"
        case .topLeft, .topRight, .bottomLeft, .bottomRight: "Quarters"
        case .full, .center: "Fill & Center"
        case .grow, .shrink, .resize: "Resize"
        case .scroll, .arrows: "Scroll"
        case .copy, .cut, .copyWord, .cutWord, .paste, .undo, .redo, .selectAll, .select, .deselect, .lineStart, .lineEnd: "Edit"
        case .pointer, .pointerStep, .hints: "Pointer"
        case .volume, .playPause, .nextTrack, .prevTrack, .skipForward, .skipBack: "Sound"
        case .settings: "Other"
        }
    }

    // nil when the command takes no argument.
    var argHint: String? {
        switch self {
        case .open: "app"
        case .focus: "app <left> <down> <up> <right>"
        case .desktop, .move: "1-9 <left> <right>"
        case .tab: "<left> <right> <up> <down> f c"
        case .resize: "<left> <right> <up> <down>"
        case .scroll: "<down> <up> <left> <right>"
        case .tabs: "<left> <right>"
        case .arrows: "<left> <down> <up> <right>"
        case .copy, .cut: "<left> <right> <down> a"
        case .copyWord, .cutWord: "<left> <right>"
        case .deselect: "<left> <right>"
        case .select: "<left> <right> <down>"
        case .pointer, .pointerStep: "<left> <down> <up> <right>"
        case .hints: "label"
        case .volume: "[app] set 0-100, <down> <up>, m, out"
        default: nil
        }
    }

    // What the argument can be, shown in the empty key cap after the command and a space:
    // one option per line, stacked or run together on one line as set in Settings.
    var argName: String? {
        switch self {
        case .open: "app"
        case .focus: "app or window title, then <left> <down> <up> <right> to pick\n<left> <down> <up> <right>  nearest window"
        case .desktop: "1-9  that desktop\n<left> <right>  next one"
        case .move: "1-9  to that desktop\n<left> <right>  to the next one"
        case .tab: "nothing  new window\n<left> <right> <up> <down> f c  placed there"
        case .resize: "<left> <right>  narrower / wider\n<up> <down>  shorter / taller"
        case .scroll: "<down> <up>  down / up\n<left> <right>  left / right"
        case .tabs: "<left>  previous tab\n<right>  next tab"
        case .arrows: "<left> <down> <up> <right>  arrow keys"
        case .copy, .cut: "nothing  the selection\n<left> <right>  to the word's start / end\n<down>  the line\na  everything"
        case .copyWord, .cutWord: "<left>  word before\n<right>  word after"
        case .deselect: "nothing  cursor at the end\n<left>  cursor at the start"
        case .select: "<left> <right>  a word\n<down>  the line"
        case .pointer, .pointerStep: "<left> <down> <up> <right>  move\nReturn  click\nr  right click\n2  double click"
        case .hints: "label"
        case .volume: "<down> <up>  quieter / louder\nset 0-100  that volume\nm  mute\nout  output device\napp's name  first, for just that app"
        default: nil
        }
    }

    // Enter on the row fills in the trigger instead of running, so an argument can be typed.
    var argRequired: Bool { argHint != nil && ![.tab, .copy, .cut, .deselect].contains(self) }
}

struct CommandDef: Codable, Identifiable, Equatable {
    let id: String // Action.rawValue, or a UUID for an app shortcut
    var trigger: String
    var enabled = true
    var shortcut: HotKey? // app shortcuts only: the keys pressed in that app
    var name: String? // app shortcuts only, optional
    var aliases: String? // other triggers for the same command, space-separated: "full" beside "f"

    // The trigger, then any aliases: each one runs the command.
    var names: [String] { [trigger] + (aliases ?? "").split(separator: " ").map(String.init) }

    var title: String { Action(rawValue: id)?.title ?? (name.flatMap { $0.isEmpty ? nil : $0 } ?? shortcut.map { HotKey.display($0.label) } ?? "") }
    var icon: String { Action(rawValue: id)?.icon ?? "keyboard" }
    var group: String { Action(rawValue: id)?.group ?? "This App" }

    static let defaults = Action.allCases.map { CommandDef(id: $0.rawValue, trigger: $0.defaultTrigger) }

    // Sets the direction keys (left, down, up, right) and renames them inside the thirds and
    // quarters triggers, all at once so swaps like h j k l -> j k i l don't collide.
    static func setDirections(_ keys: [String], in defs: [CommandDef]) -> [CommandDef] {
        let built: Set<Action> = [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds, .topLeft, .topRight, .bottomLeft, .bottomRight]
        var map: [Character: Character] = [:]
        for (a, new) in zip(Action.directions, keys) {
            if let old = defs.first(where: { $0.id == a.rawValue })?.trigger, old.count == 1, let n = new.first {
                map[old.first!] = n
            }
        }
        return defs.map { d in
            var d = d
            guard let a = Action(rawValue: d.id) else { return d }
            if let i = Action.directions.firstIndex(of: a) { d.trigger = keys[i] }
            else if built.contains(a) { d.trigger = String(d.trigger.map { map[$0] ?? $0 }) }
            return d
        }
    }
}

// Global shortcut that opens the bar. Modifiers are Carbon flags, as RegisterEventHotKey takes them.
struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String

    static let standard = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), label: "⌥ Space")

    // nil unless Control, Option or Command is held: a bare key would fire while typing.
    // shortcut: F-keys and other special keys get a raw character as label; name them if they're used.
    init?(event e: NSEvent) {
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !f.intersection([.control, .option, .command]).isEmpty else { return nil }
        let mods: [(NSEvent.ModifierFlags, Int, String)] = [
            (.control, controlKey, "⌃"), (.option, optionKey, "⌥"), (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘"),
        ]
        let held = mods.filter { f.contains($0.0) }
        let names: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        ]
        let key = names[Int(e.keyCode)] ?? (e.charactersIgnoringModifiers ?? "?").uppercased()
        self.init(keyCode: UInt32(e.keyCode), modifiers: UInt32(held.reduce(0) { $0 | $1.1 }),
                  label: held.map(\.2).joined() + " " + key)
    }

    init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.label = label
    }

    // A key label as shown, with special keys as symbols (⇧⌘ K, ↩) or names (Shift Command K,
    // Return), as set in Settings › Keys. Labels are stored with symbols for the modifiers.
    static func display(_ s: String, symbols: Bool = Store.shared.keySymbols) -> String {
        let names = [("⌃", "Control"), ("⌥", "Option"), ("⇧", "Shift"), ("⌘", "Command"),
                     ("↩", "Return"), ("⇥", "Tab"), ("⎋", "Esc"), ("⌫", "Delete")]
        if symbols {
            return s.split(separator: " ").map { w in names.first { $0.1 == w }?.0 ?? String(w) }.joined(separator: " ")
        }
        var out = s
        for (symbol, name) in names { out = out.replacingOccurrences(of: symbol, with: " \(name) ") }
        return out.split(separator: " ").joined(separator: " ")
    }

    // The Carbon modifiers as flags for a posted key event.
    var eventFlags: CGEventFlags {
        [(controlKey, CGEventFlags.maskControl), (optionKey, .maskAlternate), (shiftKey, .maskShift), (cmdKey, .maskCommand)]
            .reduce(into: []) { f, m in if modifiers & UInt32(m.0) != 0 { f.insert(m.1) } }
    }
}

// Shortcut commands for one app, in the bar only while that app is in front.
struct AppShortcuts: Codable, Identifiable, Equatable {
    var id: String // bundle identifier
    var name: String
    var path: String // for its icon
    var commands: [CommandDef] = []
}

// How much one resize step changes a window, as fractions.
struct ResizeSteps {
    var scale: CGFloat = 0.1 // + / -: 10% bigger, and the same back down
    var edge: CGFloat = 0.05 // re: 5% of the screen per direction key
}

enum Style: String, CaseIterable {
    case bar, minimal, island, glow

    var note: String {
        switch self {
        case .bar: "Text field with a list."
        case .minimal: "Key caps only."
        case .island: "A pill around the notch."
        case .glow: "Light along the bottom edge."
        }
    }
}
// How the command list is laid out.
enum ListStyle: String, CaseIterable { case grid, grouped }
enum Position: String, CaseIterable { case top, center, bottom }

final class Store: ObservableObject {
    static let shared = Store()
    private let key = "commands"

    @Published var style = Style(rawValue: UserDefaults.standard.string(forKey: "style") ?? "") ?? .bar {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: "style") }
    }
    @Published var listStyle = ListStyle(rawValue: UserDefaults.standard.string(forKey: "listStyle") ?? "") ?? .grid {
        didSet { UserDefaults.standard.set(listStyle.rawValue, forKey: "listStyle") }
    }
    @Published var showList = UserDefaults.standard.object(forKey: "showList") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showList, forKey: "showList") }
    }
    @Published var keySymbols = UserDefaults.standard.object(forKey: "keySymbols") as? Bool ?? true { // ⌘ ↩, or Command Return
        didSet { UserDefaults.standard.set(keySymbols, forKey: "keySymbols") }
    }
    @Published var glowKeys = UserDefaults.standard.object(forKey: "glowKeys") as? Bool ?? true { // Glow style's key caps
        didSet { UserDefaults.standard.set(glowKeys, forKey: "glowKeys") }
    }
    @Published var volumeKeys = UserDefaults.standard.string(forKey: "volumeKeys") ?? "" { // down, up after vol; "" = the window keys
        didSet { UserDefaults.standard.set(volumeKeys, forKey: "volumeKeys") }
    }
    @Published var showHints = UserDefaults.standard.object(forKey: "showHints") as? Bool ?? true { // the options beside the key caps
        didSet { UserDefaults.standard.set(showHints, forKey: "showHints") }
    }
    @Published var hintsVertical = UserDefaults.standard.object(forKey: "hintsVertical") as? Bool ?? true { // argument options stacked
        didSet { UserDefaults.standard.set(hintsVertical, forKey: "hintsVertical") }
    }
    @Published var showSpaces = UserDefaults.standard.bool(forKey: "showSpaces") {
        didSet { UserDefaults.standard.set(showSpaces, forKey: "showSpaces") }
    }
    @Published var position = Position(rawValue: UserDefaults.standard.string(forKey: "position") ?? "") ?? .bottom {
        didSet { UserDefaults.standard.set(position.rawValue, forKey: "position") }
    }

    @Published var hotKey = UserDefaults.standard.data(forKey: "hotKey")
        .flatMap { try? JSONDecoder().decode(HotKey.self, from: $0) } ?? .standard {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(hotKey), forKey: "hotKey") }
    }
    @Published var growPercent = UserDefaults.standard.object(forKey: "growPercent") as? Int ?? 10 {
        didSet { UserDefaults.standard.set(growPercent, forKey: "growPercent") }
    }
    @Published var desktopInstant = UserDefaults.standard.object(forKey: "desktopInstant") as? Bool ?? true { // d + left / right: go at once, or pick then Return
        didSet { UserDefaults.standard.set(desktopInstant, forKey: "desktopInstant") }
    }
    @Published var windowPreviews = UserDefaults.standard.object(forKey: "windowPreviews") as? Bool ?? true { // b's window pictures
        didSet { UserDefaults.standard.set(windowPreviews, forKey: "windowPreviews") }
    }
    @Published var desktopPreviews = UserDefaults.standard.object(forKey: "desktopPreviews") as? Bool ?? true { // d / m's desktop strip
        didSet { UserDefaults.standard.set(desktopPreviews, forKey: "desktopPreviews") }
    }
    @Published var pointerPreview = UserDefaults.standard.object(forKey: "pointerPreview") as? Bool ?? true { // mo's area box
        didSet { UserDefaults.standard.set(pointerPreview, forKey: "pointerPreview") }
    }
    // Left, down, up, right for mo and ms; empty means the window direction keys.
    @Published var pointerKeys = UserDefaults.standard.string(forKey: "pointerKeys") ?? "" {
        didSet { UserDefaults.standard.set(pointerKeys, forKey: "pointerKeys") }
    }
    @Published var pointerStep = UserDefaults.standard.object(forKey: "pointerStep") as? Int ?? 50 { // points, for ms
        didSet { UserDefaults.standard.set(pointerStep, forKey: "pointerStep") }
    }
    @Published var edgePercent = UserDefaults.standard.object(forKey: "edgePercent") as? Int ?? 5 {
        didSet { UserDefaults.standard.set(edgePercent, forKey: "edgePercent") }
    }
    @Published var resizeNeighbors = UserDefaults.standard.object(forKey: "resizeNeighbors") as? Bool ?? true {
        didSet { UserDefaults.standard.set(resizeNeighbors, forKey: "resizeNeighbors") }
    }
    var resizeSteps: ResizeSteps { ResizeSteps(scale: CGFloat(growPercent) / 100, edge: CGFloat(edgePercent) / 100) }
    @Published var recordingHotKey = false // the shortcut is paused while a new one is typed
    @Published var hotKeyTaken = false // registering failed: another app holds this shortcut

    @Published var defs: [CommandDef] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(defs), forKey: key) }
    }
    @Published var appShortcuts = UserDefaults.standard.data(forKey: "appShortcuts")
        .flatMap { try? JSONDecoder().decode([AppShortcuts].self, from: $0) } ?? [] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(appShortcuts), forKey: "appShortcuts") }
    }

    // The bar's commands with this app in front: its shortcuts first, so they win a shared trigger.
    func defs(for bundleID: String?) -> [CommandDef] {
        (appShortcuts.first { $0.id == bundleID }?.commands ?? []) + defs
    }

    init() {
        let saved = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([CommandDef].self, from: $0) } ?? []
        // Merge so actions added in later versions show up with their defaults.
        defs = Self.repairDirections(CommandDef.defaults.map { d in saved.first { $0.id == d.id } ?? d })
    }

    // Direction keys must be four different visible characters. A stray space once got in (the key
    // cap had focus as Settings opened), breaking the thirds and quarters built from it too:
    // then those triggers go back to their defaults, keeping whether each is on.
    static func repairDirections(_ defs: [CommandDef]) -> [CommandDef] {
        let keys = Action.directions.map { a in defs.first { $0.id == a.rawValue }?.trigger ?? "" }
        guard keys.contains(where: { $0.count != 1 || $0 == " " }) || Set(keys).count != 4 else { return defs }
        let built = Action.directions + [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds, .topLeft, .topRight, .bottomLeft, .bottomRight]
        return defs.map { d in
            guard let a = Action(rawValue: d.id), built.contains(a) else { return d }
            var d = d
            d.trigger = a.defaultTrigger
            return d
        }
    }

    // One direction key as a text field binding; keeps the last typed character.
    func directionKey(_ a: Action) -> Binding<String> {
        Binding(get: { self.defs.first { $0.id == a.rawValue }?.trigger ?? "" }, set: { v in
            guard let k = v.last.map(String.init), k != " ", let i = Action.directions.firstIndex(of: a) else { return }
            var keys = Action.directions.map { a in self.defs.first { $0.id == a.rawValue }?.trigger ?? "" }
            keys[i] = k
            self.defs = CommandDef.setDirections(keys, in: self.defs)
        })
    }

    func problem(_ d: CommandDef) -> String? {
        guard d.enabled else { return nil }
        if d.trigger.isEmpty { return "Needs a trigger" }
        if d.trigger.contains(" ") { return "Triggers can't contain spaces" }
        if let other = defs.first(where: { $0.id != d.id && $0.enabled && !Set($0.names).isDisjoint(with: d.names) }) {
            return "Same trigger as \(Action(rawValue: other.id)?.title ?? other.id)"
        }
        return nil
    }
}

struct GeneralSettings: View {
    @ObservedObject var store = Store.shared

    var directionKeys: String {
        Action.directions.map { a in store.defs.first { $0.id == a.rawValue }?.trigger ?? "" }.joined()
    }
    var directionPreset: Binding<String> {
        Binding(get: { directionKeys }, set: { p in store.defs = CommandDef.setDirections(Array(p).map(String.init), in: store.defs) })
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Open the command bar") { ShortcutRecorder() }
                if store.hotKeyTaken {
                    Text("Taken by another app.")
                        .font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Click, then press new keys.")
                    .settingsFooter()
            }
            // Used across commands (halves, thirds, quarters, d, m, re, s, vol…), so here, not in Windows.
            Section {
                Picker("Preset", selection: directionPreset) {
                    ForEach(WindowSettings.presets, id: \.0) { Text($0.1).tag($0.0) }
                    if !WindowSettings.presets.contains(where: { $0.0 == directionKeys }) { Text("Custom").tag(directionKeys) }
                }
                LabeledContent("Left, down, up, right") {
                    HStack(spacing: 6) {
                        ForEach(Action.directions, id: \.self) { a in
                            KeyCapField(text: store.directionKey(a), label: a.title)
                        }
                    }
                }
            } header: {
                Text("Direction Keys")
            } footer: {
                Text("Used by every command. Arrows always work.")
                    .settingsFooter()
            }
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Style")
                    ChoiceCards(selection: $store.style, choices: [
                        (.bar, "Command bar", AnyView(StylePicture.bar)),
                        (.minimal, "Minimal", AnyView(StylePicture.minimal)),
                        (.island, "Dynamic Island", AnyView(StylePicture.island)),
                        (.glow, "Glow", AnyView(StylePicture.glow)),
                    ])
                }
                if store.style == .minimal {
                    Picker("Position", selection: $store.position) {
                        ForEach(Position.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                }
            } header: {
                Text("Command Bar")
            } footer: {
                Text(store.style.note)
                    .settingsFooter()
            }
            if store.style == .minimal || store.style == .glow {
                Section("Key Caps") {
                    if store.style == .glow {
                        Toggle("Show key caps", isOn: $store.glowKeys)
                    }
                    if store.style == .minimal || store.glowKeys {
                        Toggle("Space as a key", isOn: $store.showSpaces)
                        Toggle("Options", isOn: $store.showHints)
                        if store.showHints {
                            Picker("Options layout", selection: $store.hintsVertical) {
                                Text("Vertical").tag(true)
                                Text("Horizontal").tag(false)
                            }
                        }
                    }
                }
            }
            Section {
                Toggle("Command list", isOn: $store.showList)
                if store.showList {
                    Picker("List layout", selection: $store.listStyle) {
                        Text("Grid").tag(ListStyle.grid)
                        Text("Grouped").tag(ListStyle.grouped)
                    }
                }
                Toggle("Window previews", isOn: $store.windowPreviews)
                Toggle("Desktop previews", isOn: $store.desktopPreviews)
            } header: {
                Text("Show")
            }
            UpdateSection()
        }
        .formStyle(.grouped)
    }
}

// Text naming commands, each shown as its current trigger in a key cap, so a renamed
// trigger reads right: CommandText("Desktop strip in", [.desktop, .move]).
struct CommandText: View {
    @ObservedObject var store = Store.shared
    let before: String
    let actions: [Action]
    let after: String
    init(_ before: String, _ actions: [Action], _ after: String = "") {
        (self.before, self.actions, self.after) = (before, actions, after)
    }

    var body: some View {
        HStack(spacing: 4) {
            if !before.isEmpty { Text(before) }
            ForEach(actions, id: \.self) { a in KeyCap(store.defs.first { $0.id == a.rawValue }?.trigger ?? "") }
            if !after.isEmpty { Text(after) }
        }
    }
}

// A switch with a subtitle, centered on both lines; a plain Toggle lines it up with the title only.
struct SubtitledToggle<Subtitle: View>: View {
    let title: String
    @Binding var isOn: Bool
    let subtitle: Subtitle
    init(_ title: String, isOn: Binding<Bool>, @ViewBuilder subtitle: () -> Subtitle) {
        (self.title, _isOn, self.subtitle) = (title, isOn, subtitle())
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                subtitle.settingsFooter()
            }
            Spacer()
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

struct UpdateSection: View {
    @ObservedObject var updater = Updater.shared

    var body: some View {
        let current = Updater.current
        Section {
            LabeledContent("Version", value: current ?? "Development build")
            LabeledContent(statusText) {
                HStack {
                    if let r = updater.latest {
                        Link("What's New", destination: r.page)
                        Button("Install") { updater.install() }.disabled(updater.status == .installing)
                    }
                    Button("Check for Updates") { updater.check() }
                        .disabled(current == nil || updater.status == .checking || updater.status == .installing)
                }
            }
            Toggle("Auto-update", isOn: $updater.auto).disabled(current == nil)
        } header: {
            Text("Updates")
        } footer: {
            Text(current == nil
                 ? "Updates work in Normalcy.app, not when run from source."
                 : "Checks once a day, and never installs on its own.")
                .settingsFooter()
        }
    }

    var statusText: String {
        switch updater.status {
        case .idle: ""
        case .checking: "Checking…"
        case .upToDate: "Normalcy is up to date"
        case .available: "Version \(updater.latest?.version ?? "") is available"
        case .installing: "Downloading and installing…"
        case .failed(let why): why
        }
    }
}

// Commands that aren't about window position or size.
struct CommandSettings: View {
    @ObservedObject var store = Store.shared

    // One of mo / ms's own direction keys, showing the window key while none are set.
    func pointerKey(_ i: Int) -> Binding<String> {
        let current = {
            store.pointerKeys.count == 4 ? Array(store.pointerKeys).map(String.init)
                : Action.directions.map { a in store.defs.first { $0.id == a.rawValue }?.trigger ?? "" }
        }
        return Binding(get: { current()[i] }, set: { v in
            // r and 2 pick the click; one key can't mean two directions.
            guard let k = v.last.map({ String($0).lowercased() }), k.count == 1, !["r", "2", " "].contains(k) else { return }
            var keys = current()
            guard !keys.enumerated().contains(where: { $0.offset != i && $0.element == k }) else { return }
            keys[i] = k
            store.pointerKeys = keys.joined()
        })
    }

    // vol's own down / up key, showing the window's down / up key while none are set.
    func volumeKey(_ i: Int) -> Binding<String> {
        let current = {
            store.volumeKeys.count == 2 ? Array(store.volumeKeys).map(String.init) // "" or "all": the window's
                : [Action.bottom, .top].map { a in store.defs.first { $0.id == a.rawValue }?.trigger ?? "" }
        }
        return Binding(get: { current()[i] }, set: { v in
            guard let k = v.last.map({ String($0).lowercased() }), k != " " else { return }
            var keys = current()
            guard keys[1 - i] != k else { return } // one key can't mean both
            keys[i] = k
            store.volumeKeys = keys.joined()
        })
    }

    var body: some View {
        CommandGroups(groups: ["Apps", "Desktops & Tabs", "Edit", "Scroll", "Pointer", "Sound", "Other"],
                      note: "Click a key cap to change it.",
                      options: ["Desktops & Tabs": GroupOptions(rows: AnyView(desktopOptions)),
                                "Pointer": GroupOptions(rows: AnyView(pointerOptions), note: "Uppercase: 10 points."),
                                "Sound": GroupOptions(rows: AnyView(soundOptions), note: "5% per press.")])
    }

    @ViewBuilder var desktopOptions: some View {
        Picker(selection: $store.desktopInstant) {
            Text("Switch as you press").tag(true)
            Text("Pick, then Return").tag(false)
        } label: {
            CommandText("", [.desktop], "left / right")
        }
    }

    @ViewBuilder var pointerOptions: some View {
        Stepper(value: $store.pointerStep, in: 10...400, step: 10) {
            LabeledContent { Text("\(store.pointerStep) points") } label: { CommandText("", [.pointerStep], "step") }
        }
        SubtitledToggle("Show area", isOn: $store.pointerPreview) { CommandText("Box around what's left in", [.pointer]) }
        Picker("Direction keys", selection: $store.pointerKeys) {
            Text("Windows").tag("")
            ForEach(WindowSettings.presets, id: \.0) { Text($0.1).tag($0.0) }
            if !store.pointerKeys.isEmpty, !WindowSettings.presets.contains(where: { $0.0 == store.pointerKeys }) {
                Text("Custom").tag(store.pointerKeys)
            }
        }
        LabeledContent("Left, down, up, right") {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    KeyCapField(text: pointerKey(i), label: Action.directions[i].title)
                }
            }
        }
    }

    @ViewBuilder var soundOptions: some View {
        Picker("Keys", selection: $store.volumeKeys) {
            Text("Down, up").tag("")
            Text("All four").tag("all")
            if !["", "all"].contains(store.volumeKeys) { Text("Custom").tag(store.volumeKeys) }
        }
        LabeledContent("Quieter, louder") {
            HStack(spacing: 6) {
                KeyCapField(text: volumeKey(0), label: "Quieter")
                KeyCapField(text: volumeKey(1), label: "Louder")
            }
        }
    }
}

struct WindowSettings: View {
    @ObservedObject var store = Store.shared
    // Direction keys in left, down, up, right order.
    static let presets = [("hjkl", "H J K L"), ("aswd", "W A S D"), ("jkil", "I J K L")]

    var body: some View {
        CommandGroups(groups: ["Halves", "Thirds", "Quarters", "Fill & Center", "Resize"],
                      note: "Thirds and quarters follow the direction keys (General).",
                      options: ["Resize": GroupOptions(rows: AnyView(resizeOptions))])
    }

    @ViewBuilder var resizeOptions: some View {
        Stepper(value: $store.growPercent, in: 1...50) {
            LabeledContent { Text("\(store.growPercent)%") } label: { CommandText("", [.grow, .shrink], "step") }
        }
        Stepper(value: $store.edgePercent, in: 1...25) {
            LabeledContent { Text("\(store.edgePercent)% of screen") } label: { CommandText("", [.resize], "step") }
        }
        SubtitledToggle("Resize neighbor", isOn: $store.resizeNeighbors) { CommandText("The window beside it changes too, in", [.resize]) }
    }
}

struct KeySettings: View {
    @ObservedObject var store = Store.shared
    // Fixed keys, listed so they can be found. Keep in sync with PaletteView.field's key handling.
    // Each entry: the key combinations that do it (alternatives), and what they do.
    let barKeys: [([[String]], String)] = [
        ([["Return"]], "Run the command"),
        ([["⇧", "Return"]], "Run it and keep the bar open"),
        ([["Tab"], ["⌃", "N"]], "Next in the list"),
        ([["⇧", "Tab"], ["⌃", "P"]], "Previous in the list"),
        ([["←", "↓", "↑", "→"]], "Same as the direction keys"),
        ([["Esc"]], "Clear what you typed, or close when empty"),
        ([["⌃", "U"]], "Clear what you typed"),
        ([["⌃", "W"]], "Delete the last word"),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Special keys", selection: $store.keySymbols) {
                    Text("⌘ ⌥ ↩").tag(true)
                    Text("Command Option Return").tag(false)
                }
            }
            Section {
                ForEach(barKeys, id: \.1) { combos, what in
                    LabeledContent(what) {
                        HStack(spacing: 4) {
                            ForEach(Array(combos.enumerated()), id: \.offset) { i, keys in
                                if i > 0 { Text("or").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4) }
                                ForEach(keys, id: \.self) { KeyCap(HotKey.display($0, symbols: store.keySymbols)) }
                            }
                        }
                    }
                }
            } header: {
                Text("In the Command Bar")
            } footer: {
                Text("Fixed.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
    }
}

// A page of command groups, with optional sections before and after, and a reset for just
// these commands.
// Settings that belong to one group of commands, shown under its rows.
struct GroupOptions {
    let rows: AnyView
    var note: String?
}

struct CommandGroups<Before: View, After: View>: View {
    @ObservedObject var store = Store.shared
    let groups: [String]
    let note: String
    let options: [String: GroupOptions]
    @ViewBuilder var before: Before
    @ViewBuilder var after: After

    init(groups: [String], note: String, options: [String: GroupOptions] = [:],
         @ViewBuilder before: () -> Before = { EmptyView() }, @ViewBuilder after: () -> After = { EmptyView() }) {
        self.groups = groups
        self.note = note
        self.options = options
        self.before = before()
        self.after = after()
    }

    // Groups folded away, kept between launches.
    @AppStorage("hiddenGroups") private var hiddenList = ""
    var hidden: Set<String> { Set(hiddenList.split(separator: "|").map(String.init)) }

    // Click to show or hide the group's commands. Folded, it shows how many there are, and a
    // warning if one of them has a trigger problem.
    func groupHeader(_ g: String, count: Int, open: Bool, problem: Bool) -> some View {
        Button {
            var h = hidden
            if open { h.insert(g) } else { h.remove(g) }
            withAnimation(.easeOut(duration: 0.2)) { hiddenList = h.sorted().joined(separator: "|") }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .foregroundStyle(.secondary)
                Text(g).font(.system(size: 13, weight: .bold)).foregroundStyle(.primary)
                if !open {
                    Text("\(count)").font(.system(size: 13)).foregroundStyle(.secondary)
                    if problem { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }
                Spacer()
            }
            // Fixed size and spacing: a Form shrinks the headers of sections left empty, as folded ones are.
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(g)
        .accessibilityValue(open ? "shown" : "hidden, \(count) commands")
        .accessibilityHint(open ? "Hides its commands" : "Shows its commands")
    }

    var body: some View {
        Form {
            before
            ForEach(groups, id: \.self) { g in
                let rows = store.defs.indices.filter { Action(rawValue: store.defs[$0].id)?.group == g }
                let open = !hidden.contains(g)
                Section {
                    if open {
                        ForEach(rows, id: \.self) { i in
                            let a = Action(rawValue: store.defs[i].id)!
                            CommandRow(def: $store.defs[i],
                                       trigger: Action.directions.contains(a) ? store.directionKey(a) : $store.defs[i].trigger,
                                       problem: store.problem(store.defs[i]))
                        }
                    }
                } header: {
                    groupHeader(g, count: rows.count, open: open,
                                problem: !open && rows.contains { store.problem(store.defs[$0]) != nil })
                }
                // The group's own settings, right under its commands and folded with them.
                if open, let o = options[g] {
                    Section {
                        o.rows
                    } header: {
                        Label("\(g) settings", systemImage: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 14)
                    } footer: {
                        if let note = o.note { Text(note).settingsFooter() }
                    }
                }
            }
            after
            Section {} footer: {
                HStack(alignment: .top) {
                    Text(note)
                        .settingsFooter()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Reset These") {
                        let mine = Set(Action.allCases.filter { groups.contains($0.group) }.map(\.rawValue))
                        store.defs = store.defs.map { d in mine.contains(d.id) ? CommandDef.defaults.first { $0.id == d.id }! : d }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct CommandRow: View {
    @Binding var def: CommandDef
    @Binding var trigger: String // the def's trigger, or a direction key that renames others too
    let problem: String?

    var body: some View {
        let a = Action(rawValue: def.id)
        HStack(spacing: 12) {
            Image(systemName: a?.icon ?? "questionmark")
                .font(.system(size: 15))
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(a?.title ?? def.id)
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 12)
            KeyCapField(text: Binding(get: { def.aliases ?? "" }, set: { def.aliases = $0.isEmpty ? nil : $0 }),
                        label: "Other triggers for \(a?.title ?? def.id), separated by spaces")
                .disabled(!def.enabled)
            KeyCapField(text: $trigger, label: "Trigger for \(a?.title ?? def.id)", invalid: problem != nil)
                .disabled(!def.enabled)
            Toggle("Use \(a?.title ?? def.id)", isOn: $def.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .opacity(def.enabled ? 1 : 0.55)
    }
}

// Shortcuts you already know in an app, each turned into a trigger for the bar.
struct AppShortcutSettings: View {
    @ObservedObject var store = Store.shared

    var body: some View {
        Form {
            ForEach($store.appShortcuts) { $app in
                Section {
                    ForEach($app.commands) { $c in
                        AppShortcutRow(def: $c, problem: problem(c, in: app)) {
                            $app.wrappedValue.commands.removeAll { $0.id == c.id }
                        }
                    }
                    Button("Add Shortcut") { $app.wrappedValue.commands.append(CommandDef(id: UUID().uuidString, trigger: "")) }
                } header: {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 18, height: 18)
                        Text(app.name)
                        Spacer()
                        Button("Remove \(app.name)", systemImage: "minus.circle") {
                            store.appShortcuts.removeAll { $0.id == app.id }
                        }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                }
            }
            Section {} footer: {
                HStack(alignment: .top) {
                    Text("Shows only while its app is in front.")
                        .settingsFooter()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Add App…", action: addApp)
                }
            }
        }
        .formStyle(.grouped)
    }

    func problem(_ c: CommandDef, in app: AppShortcuts) -> String? {
        guard c.enabled else { return nil }
        if c.trigger.isEmpty { return "Needs a trigger" }
        if c.trigger.contains(" ") { return "Triggers can't contain spaces" }
        if c.shortcut == nil { return "Click Record, then press the shortcut" }
        if app.commands.contains(where: { $0.id != c.id && $0.enabled && $0.trigger == c.trigger }) { return "Same trigger as another shortcut here" }
        return nil
    }

    func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        guard !store.appShortcuts.contains(where: { $0.id == id }) else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        store.appShortcuts.append(AppShortcuts(id: id, name: name, path: url.path,
                                               commands: [CommandDef(id: UUID().uuidString, trigger: "")]))
    }
}

struct AppShortcutRow: View {
    @Binding var def: CommandDef
    let problem: String?
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            KeyCapField(text: $def.trigger, label: "Trigger", invalid: problem != nil && !def.trigger.isEmpty)
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: Binding(get: { def.name ?? "" }, set: { def.name = $0 }), prompt: Text("Name (optional)"))
                    .labelsHidden()
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            KeyRecorder(key: $def.shortcut)
            Toggle("Use", isOn: $def.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
            Button("Delete", systemImage: "trash", action: remove).labelStyle(.iconOnly).buttonStyle(.borderless)
        }
        .opacity(def.enabled ? 1 : 0.55)
    }
}

// Click, then press a shortcut for an app command. Esc cancels.
struct KeyRecorder: View {
    @Binding var key: HotKey?
    @ObservedObject var store = Store.shared
    @State private var monitor: Any?

    var body: some View {
        Button(monitor != nil ? "Type shortcut…" : key.map { HotKey.display($0.label, symbols: store.keySymbols) } ?? "Record") { monitor != nil ? stop() : start() }
            .font(.system(.body, design: .monospaced))
            .onDisappear(perform: stop)
    }

    func start() {
        Store.shared.recordingHotKey = true // so pressing the bar's own shortcut records it instead of opening the bar
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == UInt16(kVK_Escape) { stop() }
            else if let k = HotKey(event: e) { key = k; stop() }
            return nil // swallow keys while recording
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        Store.shared.recordingHotKey = false
    }
}

// A key drawn like a keyboard key, like the command bar's key caps.
struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: text.count == 1 ? .monospaced : .default))
            .padding(.horizontal, 7)
            .frame(minWidth: 26, minHeight: 22)
            .keyCapBackground()
    }
}

// An editable key cap: a trigger or a direction key.
// A key cap that turns into a text field only once clicked. A field there from the start takes
// focus as Settings opens, so a stray key replaced the key (and once left it drawn blank).
struct KeyCapField: View {
    @Binding var text: String
    let label: String
    var invalid = false
    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing {
                TextField(label, text: $text)
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onAppear { DispatchQueue.main.async { focused = true } }
                    .onChange(of: focused) { if !focused { editing = false } }
                    .onSubmit { focused = false }
            } else {
                Button { editing = true } label: {
                    Text(text).frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityValue(text)
                .accessibilityHint("Click, then type a new key")
            }
        }
        .font(.system(size: 13, weight: .medium, design: .monospaced))
        .multilineTextAlignment(.center)
        .frame(width: max(30, CGFloat(text.count) * 9 + 16), height: 24)
        .keyCapBackground(highlight: editing ? .accentColor : invalid ? .red : nil)
        .help(label)
    }
}

extension View {
    func keyCapBackground(highlight: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        // A lighter face over a darker bottom edge reads as a key.
        return background(
            shape.fill(Color.primary.opacity(0.12))
                .background(shape.fill(Color.black.opacity(0.4)).offset(y: 1.5))
        )
        .overlay(shape.strokeBorder(highlight ?? Color.primary.opacity(0.15), lineWidth: highlight == nil ? 0.5 : 1.5))
    }

    func settingsFooter() -> some View {
        font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

// Click, then press the new shortcut. Esc cancels.
struct ShortcutRecorder: View {
    @ObservedObject var store = Store.shared
    @State private var monitor: Any?

    var body: some View {
        HStack {
            if store.hotKey != .standard, !store.recordingHotKey {
                Button("Reset") { store.hotKey = .standard }
            }
            Button(store.recordingHotKey ? "Type shortcut…" : HotKey.display(store.hotKey.label, symbols: store.keySymbols)) {
                store.recordingHotKey ? stop() : start()
            }
            .font(.system(.body, design: .monospaced))
        }
        .onDisappear(perform: stop)
    }

    func start() {
        store.recordingHotKey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == UInt16(kVK_Escape) { stop() }
            else if let k = HotKey(event: e) { store.hotKey = k; stop() }
            return nil // swallow keys while recording
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        store.recordingHotKey = false
    }
}

// Picks one of a few looks by a small picture of each, like Appearance in System Settings.
struct ChoiceCards<Value: Hashable>: View {
    @Binding var selection: Value
    let choices: [(value: Value, title: String, picture: AnyView)]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(choices.indices, id: \.self) { i in
                let c = choices[i], on = c.value == selection
                let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
                Button { selection = c.value } label: {
                    VStack(spacing: 7) {
                        c.picture
                            .frame(maxWidth: .infinity)
                            .frame(height: 66)
                            .background(shape.fill(Color.primary.opacity(0.06)))
                            .clipShape(shape)
                            .overlay(shape.strokeBorder(on ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: on ? 2.5 : 1))
                        Text(c.title)
                            .font(.system(size: 11, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(c.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 2)
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

// Little drawings of each bar style, standing for a screen.
enum StylePicture {
    static let ink = Color.primary.opacity(0.55)
    static let faint = Color.primary.opacity(0.18)

    static func cap(_ w: CGFloat = 10) -> some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(faint).frame(width: w, height: 10)
            .overlay(RoundedRectangle(cornerRadius: 2.5, style: .continuous).strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
    }

    static var bar: some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 3).fill(ink).frame(width: 64, height: 8)
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5).fill(faint).frame(width: 64 - CGFloat(i) * 12, height: 4)
                    .frame(width: 64, alignment: .leading)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
    }

    static var minimal: some View {
        VStack {
            Spacer()
            HStack(spacing: 3) { cap(); cap(18); cap() }.padding(.bottom, 9)
        }
    }

    static var island: some View {
        VStack {
            UnevenRoundedRectangle(bottomLeadingRadius: 7, bottomTrailingRadius: 7)
                .fill(.black).frame(width: 52, height: 13)
                .overlay(Capsule().fill(.white.opacity(0.7)).frame(width: 22, height: 3))
            Spacer()
        }
    }

    static var glow: some View {
        VStack(spacing: 5) {
            Spacer()
            LinearGradient(colors: [.blue, .purple, .pink, .orange], startPoint: .leading, endPoint: .trailing)
                .frame(height: 5).blur(radius: 3).opacity(0.9)
        }
    }
}
