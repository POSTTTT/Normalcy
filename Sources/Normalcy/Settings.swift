import SwiftUI

enum Action: String, CaseIterable {
    case open, focus, desktop, left, right, top, bottom, full, center, settings

    var defaultTrigger: String {
        switch self {
        case .open: "o"
        case .focus: "b"
        case .desktop: "d"
        case .left: "h"
        case .right: "l"
        case .top: "k"
        case .bottom: "j"
        case .full: "f"
        case .center: "c"
        case .settings: "set"
        }
    }

    var help: String {
        switch self {
        case .open: "Open app — <trigger> Safari"
        case .focus: "Switch to running app — <trigger> saf"
        case .desktop: "Go to desktop — <trigger> 2 / h / l"
        case .left: "Window: left half"
        case .right: "Window: right half"
        case .top: "Window: top half"
        case .bottom: "Window: bottom half"
        case .full: "Window: full screen"
        case .center: "Window: center"
        case .settings: "Open these settings"
        }
    }
}

struct CommandDef: Codable, Identifiable, Equatable {
    let id: String // Action.rawValue
    var trigger: String
    var enabled = true

    static let defaults = Action.allCases.map { CommandDef(id: $0.rawValue, trigger: $0.defaultTrigger) }
}

final class Store: ObservableObject {
    static let shared = Store()
    private let key = "commands"

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
        if d.trigger.isEmpty { return "empty" }
        if d.trigger.contains(" ") { return "no spaces" }
        if defs.contains(where: { $0.id != d.id && $0.enabled && $0.trigger == d.trigger }) { return "duplicate" }
        return nil
    }
}

struct SettingsView: View {
    @ObservedObject var store = Store.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Show").frame(width: 40, alignment: .leading)
                Text("Trigger").frame(width: 90, alignment: .leading)
                Text("Action")
            }
            .font(.caption).foregroundStyle(.secondary)
            ForEach($store.defs) { $d in
                HStack {
                    Toggle("", isOn: $d.enabled).labelsHidden().frame(width: 40, alignment: .leading)
                    TextField("", text: $d.trigger)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 80)
                        .disabled(!d.enabled)
                        .padding(.trailing, 10)
                    Text(Action(rawValue: d.id)?.help ?? d.id)
                        .foregroundStyle(d.enabled ? .primary : .secondary)
                    Spacer()
                    if let p = store.problem(d) { Text(p).foregroundStyle(.red).font(.caption) }
                }
            }
            HStack {
                Spacer()
                Button("Reset to Defaults") { store.defs = CommandDef.defaults }
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
