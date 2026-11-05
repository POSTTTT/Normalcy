import Carbon
import SwiftUI

enum Action: String, CaseIterable {
    case open, focus, desktop, move, tab, left, right, top, bottom, full, center
    case leftThird, centerThird, rightThird, topLeft, topRight, bottomLeft, bottomRight
    case grow, shrink, resize
    case scroll
    case pointer, pointerStep
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
        case .left: "h"
        case .right: "l"
        case .top: "k"
        case .bottom: "j"
        case .full: "f"
        case .center: "c"
        case .leftThird: "h3"
        case .centerThird: "c3"
        case .rightThird: "l3"
        case .topLeft: "hk"
        case .topRight: "lk"
        case .bottomLeft: "hj"
        case .bottomRight: "lj"
        case .grow: "+"
        case .shrink: "-"
        case .resize: "re"
        case .scroll: "s"
        case .pointer: "mo"
        case .pointerStep: "ms"
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
        case .left: "Left Half"
        case .right: "Right Half"
        case .top: "Top Half"
        case .bottom: "Bottom Half"
        case .full: "Fill Screen"
        case .center: "Center"
        case .leftThird: "Left Third"
        case .centerThird: "Center Third"
        case .rightThird: "Right Third"
        case .topLeft: "Top Left Quarter"
        case .topRight: "Top Right Quarter"
        case .bottomLeft: "Bottom Left Quarter"
        case .bottomRight: "Bottom Right Quarter"
        case .grow: "Make Bigger"
        case .shrink: "Make Smaller"
        case .resize: "Resize by Direction"
        case .scroll: "Scroll"
        case .pointer: "Pointer by Halves"
        case .pointerStep: "Pointer by Steps"
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
        case .left: "rectangle.lefthalf.filled"
        case .right: "rectangle.righthalf.filled"
        case .top: "rectangle.tophalf.filled"
        case .bottom: "rectangle.bottomhalf.filled"
        case .full: "rectangle.fill"
        case .center: "rectangle.center.inset.filled"
        case .leftThird: "rectangle.leadingthird.inset.filled"
        case .centerThird: "rectangle.split.3x1"
        case .rightThird: "rectangle.trailingthird.inset.filled"
        case .topLeft: "rectangle.inset.topleft.filled"
        case .topRight: "rectangle.inset.topright.filled"
        case .bottomLeft: "rectangle.inset.bottomleft.filled"
        case .bottomRight: "rectangle.inset.bottomright.filled"
        case .grow: "arrow.up.left.and.arrow.down.right"
        case .shrink: "arrow.down.right.and.arrow.up.left"
        case .resize: "arrow.up.and.down.and.arrow.left.and.right"
        case .scroll: "scroll"
        case .pointer: "cursorarrow.rays"
        case .pointerStep: "cursorarrow.motionlines"
        case .settings: "gearshape"
        }
    }

    // Window placement and sizing: shown as tiles in the grid list.
    var isWindow: Bool { ["Halves", "Thirds", "Quarters", "Fill & Center", "Resize"].contains(group) }

    // Section the command is listed under in Settings.
    var group: String {
        switch self {
        case .open, .focus: "Apps"
        case .desktop, .move, .tab: "Desktops & Tabs"
        case .left, .right, .top, .bottom: "Halves"
        case .leftThird, .centerThird, .rightThird: "Thirds"
        case .topLeft, .topRight, .bottomLeft, .bottomRight: "Quarters"
        case .full, .center: "Fill & Center"
        case .grow, .shrink, .resize: "Resize"
        case .scroll: "Scroll"
        case .pointer, .pointerStep: "Pointer"
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
        case .pointer, .pointerStep: "<left> <down> <up> <right>"
        default: nil
        }
    }

    // What the argument is, shown in the empty key cap after the command and a space.
    var argName: String? {
        switch self {
        case .open: "app"
        case .focus: "app or direction"
        case .desktop, .move: "number or direction"
        case .tab: "position"
        case .resize, .scroll: "direction"
        case .pointer, .pointerStep: "direction, Return clicks"
        default: nil
        }
    }

    // Enter on the row fills in the trigger instead of running, so an argument can be typed.
    var argRequired: Bool { argHint != nil && self != .tab }

    // Usage shown under the command in Settings; <trigger> is replaced with the current trigger.
    var example: String? {
        switch self {
        case .open: "<trigger> Safari"
        case .focus: "<trigger> saf — matches the start of the app name; <trigger> <left> <down> <up> <right> switches to the nearest window that way"
        case .desktop, .move: "<trigger> 2, or <trigger> <left> / <trigger> <right> for left / right"
        case .tab: "<trigger>, or <trigger> <left> to put the new window on the left"
        case .scroll: "<trigger>, then <down> <up> <left> <right> scroll as you press them; Esc to stop"
        case .pointer: "<trigger>, then each of <left> <down> <up> <right> keeps that half of the screen and puts the pointer in its middle; uppercase nudges, Space starts over from the center. Return clicks, r then Return right-clicks, 2 then Return double-clicks"
        case .pointerStep: "<trigger>, then <left> <down> <up> <right> move the pointer by the step set below, uppercase 10 points. Return clicks, r then Return right-clicks, 2 then Return double-clicks"
        case .resize: "<trigger> <left> <right> <up> <down> moves the window's free edge that way: its right or bottom edge, or the left or top edge of a window against the right or bottom of the screen"
        default: nil
        }
    }
}

struct CommandDef: Codable, Identifiable, Equatable {
    let id: String // Action.rawValue
    var trigger: String
    var enabled = true

    static let defaults = Action.allCases.map { CommandDef(id: $0.rawValue, trigger: $0.defaultTrigger) }

    // Sets the direction keys (left, down, up, right) and renames them inside the thirds and
    // quarters triggers, all at once so swaps like h j k l -> j k i l don't collide.
    static func setDirections(_ keys: [String], in defs: [CommandDef]) -> [CommandDef] {
        let built: Set<Action> = [.leftThird, .centerThird, .rightThird, .topLeft, .topRight, .bottomLeft, .bottomRight]
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
}

// How much one resize step changes a window, as fractions.
struct ResizeSteps {
    var scale: CGFloat = 0.1 // + / -: 10% bigger, and the same back down
    var edge: CGFloat = 0.05 // re: 5% of the screen per direction key
}

enum Style: String, CaseIterable { case bar, minimal }
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

    init() {
        let saved = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([CommandDef].self, from: $0) } ?? []
        // Merge so actions added in later versions show up with their defaults.
        defs = CommandDef.defaults.map { d in saved.first { $0.id == d.id } ?? d }
    }

    // One direction key as a text field binding; keeps the last typed character.
    func directionKey(_ a: Action) -> Binding<String> {
        Binding(get: { self.defs.first { $0.id == a.rawValue }?.trigger ?? "" }, set: { v in
            guard let k = v.last.map(String.init), let i = Action.directions.firstIndex(of: a) else { return }
            var keys = Action.directions.map { a in self.defs.first { $0.id == a.rawValue }?.trigger ?? "" }
            keys[i] = k
            self.defs = CommandDef.setDirections(keys, in: self.defs)
        })
    }

    func problem(_ d: CommandDef) -> String? {
        guard d.enabled else { return nil }
        if d.trigger.isEmpty { return "Needs a trigger" }
        if d.trigger.contains(" ") { return "Triggers can't contain spaces" }
        if let other = defs.first(where: { $0.id != d.id && $0.enabled && $0.trigger == d.trigger }) {
            return "Same trigger as \(Action(rawValue: other.id)?.title ?? other.id)"
        }
        return nil
    }
}

struct GeneralSettings: View {
    @ObservedObject var store = Store.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Open the command bar") { ShortcutRecorder() }
                if store.hotKeyTaken {
                    Text("Another app already uses this shortcut. Pick a different one.")
                        .font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Works from any app. Click the shortcut, then press the new one.")
                    .settingsFooter()
            }
            Section {
                Picker("Style", selection: $store.style) {
                    Text("Command bar").tag(Style.bar)
                    Text("Minimal").tag(Style.minimal)
                }
                .pickerStyle(.segmented)
                if store.style == .minimal {
                    Picker("Position on screen", selection: $store.position) {
                        ForEach(Position.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Toggle("Show each space as its own key", isOn: $store.showSpaces)
                }
                Toggle("Show the command list", isOn: $store.showList)
                if store.showList {
                    Picker("List layout", selection: $store.listStyle) {
                        Text("Rows with a layout grid").tag(ListStyle.grid)
                        Text("Grouped, scrolling").tag(ListStyle.grouped)
                    }
                }
            } header: {
                Text("Command Bar")
            } footer: {
                Text(store.style == .bar
                     ? "Command bar shows a text field with the list under it."
                     : "Minimal hides the text field and shows what you type as key caps.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
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

    var body: some View {
        CommandGroups(groups: ["Apps", "Desktops & Tabs", "Scroll", "Pointer", "Other"],
                      note: "The key cap is what you type. Click it to change it; switch a command off to hide it.") {
            EmptyView()
        } after: {
            Section {
                Stepper(value: $store.pointerStep, in: 10...400, step: 10) {
                    LabeledContent("Each direction key after ms", value: "\(store.pointerStep) points")
                }
                Toggle("Show the area left after mo", isOn: $store.pointerPreview)
                Picker("Direction keys", selection: $store.pointerKeys) {
                    Text("Same as windows").tag("")
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
            } header: {
                Text("Pointer")
            } footer: {
                Text("Uppercase keys always move 10 points, for the last bit. r and 2 are kept for clicks.")
                    .settingsFooter()
            }
        }
    }
}

struct WindowSettings: View {
    @ObservedObject var store = Store.shared
    // Direction keys in left, down, up, right order.
    static let presets = [("hjkl", "H J K L"), ("aswd", "W A S D"), ("jkil", "I J K L")]

    var body: some View {
        let currentKeys = Action.directions.map { a in store.defs.first { $0.id == a.rawValue }?.trigger ?? "" }.joined()
        let presetBinding = Binding(get: { currentKeys }, set: { (p: String) in
            store.defs = CommandDef.setDirections(Array(p).map(String.init), in: store.defs)
        })
        CommandGroups(groups: ["Halves", "Thirds", "Quarters", "Fill & Center", "Resize"],
                      note: "Thirds and quarters are built from the direction keys, so changing those renames them too.") {
            Section {
                Picker("Preset", selection: presetBinding) {
                    ForEach(Self.presets, id: \.0) { Text($0.1).tag($0.0) }
                    if !Self.presets.contains(where: { $0.0 == currentKeys }) { Text("Custom").tag(currentKeys) }
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
                Text("Used for halves, thirds and quarters, and after d, m, t, re and s. Arrow keys always work too.")
                    .settingsFooter()
            }
        } after: {
            Section {
                Stepper(value: $store.growPercent, in: 1...50) {
                    LabeledContent("Bigger or smaller (+ −)", value: "\(store.growPercent)%")
                }
                Stepper(value: $store.edgePercent, in: 1...25) {
                    LabeledContent("Each direction key after re", value: "\(store.edgePercent)% of screen")
                }
                Toggle("Resize the window next to it too", isOn: $store.resizeNeighbors)
            } header: {
                Text("Resize Steps")
            } footer: {
                Text("With two windows side by side, growing one shrinks the other.")
                    .settingsFooter()
            }
        }
    }
}

struct KeySettings: View {
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
                ForEach(barKeys, id: \.1) { combos, what in
                    LabeledContent(what) {
                        HStack(spacing: 4) {
                            ForEach(Array(combos.enumerated()), id: \.offset) { i, keys in
                                if i > 0 { Text("or").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4) }
                                ForEach(keys, id: \.self) { KeyCap($0) }
                            }
                        }
                    }
                }
            } header: {
                Text("In the Command Bar")
            } footer: {
                Text("These keys are fixed. Command triggers are set in Commands and Windows.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
    }
}

// A page of command groups, with optional sections before and after, and a reset for just
// these commands.
struct CommandGroups<Before: View, After: View>: View {
    @ObservedObject var store = Store.shared
    let groups: [String]
    let note: String
    @ViewBuilder var before: Before
    @ViewBuilder var after: After

    init(groups: [String], note: String,
         @ViewBuilder before: () -> Before = { EmptyView() }, @ViewBuilder after: () -> After = { EmptyView() }) {
        self.groups = groups
        self.note = note
        self.before = before()
        self.after = after()
    }

    var body: some View {
        Form {
            before
            ForEach(groups, id: \.self) { g in
                Section(g) {
                    ForEach(store.defs.indices.filter { Action(rawValue: store.defs[$0].id)?.group == g }, id: \.self) { i in
                        let a = Action(rawValue: store.defs[i].id)!
                        CommandRow(def: $store.defs[i],
                                   trigger: Action.directions.contains(a) ? store.directionKey(a) : $store.defs[i].trigger,
                                   problem: store.problem(store.defs[i]))
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
                if let example = a?.example {
                    Text(Command.spell(example.replacingOccurrences(of: "<trigger>", with: def.trigger.isEmpty ? "…" : def.trigger), Store.shared.defs))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 12)
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
struct KeyCapField: View {
    @Binding var text: String
    let label: String
    var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: $text)
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .multilineTextAlignment(.center)
            .focused($focused)
            .frame(width: max(30, CGFloat(text.count) * 9 + 16), height: 24)
            .keyCapBackground(highlight: focused ? .accentColor : invalid ? .red : nil)
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
            Button(store.recordingHotKey ? "Type shortcut…" : store.hotKey.label) {
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
