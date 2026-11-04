import SwiftUI

enum Action: String, CaseIterable {
    case open, focus, desktop, move, tab, left, right, top, bottom, full, center, settings

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
        case .settings: "gearshape"
        }
    }

    // nil when the command takes no argument.
    var argHint: String? {
        switch self {
        case .open, .focus: "app"
        case .desktop, .move: "1-9 h l"
        case .tab: "h l k j f c"
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
        case .desktop, .move: "<trigger> 2, or <trigger> h / <trigger> l for left / right"
        case .tab: "<trigger>, or <trigger> h to put the new window on the left"
        default: nil
        }
    }
}

struct CommandDef: Codable, Identifiable, Equatable {
    let id: String // Action.rawValue
    var trigger: String
    var enabled = true

    static let defaults = Action.allCases.map { CommandDef(id: $0.rawValue, trigger: $0.defaultTrigger) }
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

    var body: some View {
        Form {
            Section {
                ForEach($store.defs) { $d in
                    CommandRow(def: $d, problem: store.problem(d))
                }
            } footer: {
                HStack(alignment: .top) {
                    Text("The trigger is what you type. Switch a command off to hide it.\nArrow keys work like h j k l. Tab or Ctrl+N / Ctrl+P move through the list.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset to Defaults") { store.defs = CommandDef.defaults }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct CommandRow: View {
    @Binding var def: CommandDef
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
                    Text(example.replacingOccurrences(of: "<trigger>", with: def.trigger.isEmpty ? "…" : def.trigger))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let problem {
                    Text(problem).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            TextField("Trigger", text: $def.trigger)
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
