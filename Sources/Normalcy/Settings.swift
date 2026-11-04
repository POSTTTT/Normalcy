import SwiftUI

enum Action: String, CaseIterable {
    case open, focus, desktop, move, tab, left, right, top, bottom, full, center
    case leftThird, centerThird, rightThird, topLeft, topRight, bottomLeft, bottomRight
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
        case .settings: "gearshape"
        }
    }

    // Section the command is listed under in Settings.
    var group: String {
        switch self {
        case .open, .focus: "Apps"
        case .desktop, .move, .tab: "Desktops & Tabs"
        case .left, .right, .top, .bottom: "Halves"
        case .leftThird, .centerThird, .rightThird: "Thirds"
        case .topLeft, .topRight, .bottomLeft, .bottomRight: "Quarters"
        case .full, .center: "Fill & Center"
        case .settings: "Other"
        }
    }

    // nil when the command takes no argument.
    var argHint: String? {
        switch self {
        case .open, .focus: "app"
        case .desktop, .move: "1-9 <left> <right>"
        case .tab: "<left> <right> <up> <down> f c"
        default: nil
        }
    }

    // Enter on the row fills in the trigger instead of running, so an argument can be typed.
    var argRequired: Bool { argHint != nil && self != .tab }

    // Usage shown under the command in Settings; <trigger> is replaced with the current trigger.
    var example: String? {
        switch self {
        case .open: "<trigger> Safari"
        case .focus: "<trigger> saf — matches the start of the app name"
        case .desktop, .move: "<trigger> 2, or <trigger> <left> / <trigger> <right> for left / right"
        case .tab: "<trigger>, or <trigger> <left> to put the new window on the left"
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

enum Style: String, CaseIterable { case bar, minimal }
enum Position: String, CaseIterable { case top, center, bottom }

final class Store: ObservableObject {
    static let shared = Store()
    private let key = "commands"

    @Published var style = Style(rawValue: UserDefaults.standard.string(forKey: "style") ?? "") ?? .bar {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: "style") }
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
            Section("Activation") {
                LabeledContent("Shortcut") {
                    Text("⌥ Space").font(.system(.body, design: .monospaced))
                }
            }
            Section {
                Picker("Style", selection: $store.style) {
                    Text("Command bar").tag(Style.bar)
                    Text("Minimal").tag(Style.minimal)
                }
                Toggle("Show command list", isOn: $store.showList)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Minimal hides the text field and shows what you type as key caps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Minimal style") {
                Picker("Position", selection: $store.position) {
                    ForEach(Position.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Show spaces as ␣", isOn: $store.showSpaces)
            }
            .disabled(store.style == .bar)
        }
        .formStyle(.grouped)
    }
}

struct CommandSettings: View {
    @ObservedObject var store = Store.shared
    // Direction keys in left, down, up, right order.
    let presets = [("hjkl", "H J K L"), ("aswd", "W A S D"), ("jkil", "I J K L")]

    var body: some View {
        let currentKeys = Action.directions.map { a in store.defs.first { $0.id == a.rawValue }?.trigger ?? "" }.joined()
        let presetBinding = Binding(get: { currentKeys }, set: { (p: String) in
            store.defs = CommandDef.setDirections(Array(p).map(String.init), in: store.defs)
        })
        let groups = Action.allCases.map(\.group).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        Form {
            Section("Direction Keys") {
                Picker("Preset", selection: presetBinding) {
                    ForEach(presets, id: \.0) { Text($0.1).tag($0.0) }
                    if !presets.contains(where: { $0.0 == currentKeys }) { Text("Custom").tag(currentKeys) }
                }
                LabeledContent {
                    HStack(spacing: 10) {
                        ForEach(Array(zip(Action.directions, ["←", "↓", "↑", "→"])), id: \.0) { a, arrow in
                            HStack(spacing: 4) {
                                Text(arrow).foregroundStyle(.secondary)
                                TextField(a.title, text: store.directionKey(a))
                                    .labelsHidden()
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .multilineTextAlignment(.center)
                                    .frame(width: 32)
                            }
                        }
                    }
                } label: {
                    Text("Keys")
                    Text("Halves, thirds, quarters, and the direction after d, m and t. Arrow keys always work.")
                }
            }
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
            Section {} footer: {
                HStack(alignment: .top) {
                    Text("The trigger is what you type. Switch a command off to hide it. Tab or Ctrl+N / Ctrl+P move through the list.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Reset to Defaults") { store.defs = CommandDef.defaults }
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
                    .foregroundStyle(def.enabled ? .primary : .secondary)
                if let example = a?.example {
                    Text(Command.spell(example.replacingOccurrences(of: "<trigger>", with: def.trigger.isEmpty ? "…" : def.trigger), Store.shared.defs))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let problem {
                    Text(problem).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            TextField("Trigger", text: $trigger)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(width: 64)
                .disabled(!def.enabled)
            Toggle("Show \(a?.title ?? def.id)", isOn: $def.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}
