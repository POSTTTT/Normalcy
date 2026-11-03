import SwiftUI

final class Palette: ObservableObject {
    @Published var text = "" { didSet { selected = 0 } }
    @Published var selected = 0
    @Published var focusToken = 0 // bumped on every show to refocus the field
    var submit: (String) -> Void = { _ in }
    var cancel: () -> Void = {}
    var defs: () -> [CommandDef] = { Store.shared.defs }
    @Published var desktops = Desktops()

    // The desktop-related command being typed or highlighted, if any.
    var desktopCommand: CommandDef? {
        let rows = matches
        let row = text.drop { $0 == " " }.contains(" ") ? rows.first
            : rows.indices.contains(selected) ? rows[selected] : nil
        return row.flatMap { ["desktop", "move"].contains($0.id) ? $0 : nil }
    }

    // Desktop number the typed argument points at ("2", or "h"/"l" relative to the current one).
    var desktopTarget: Int? {
        let parts = text.split(separator: " ")
        guard parts.count > 1 else { return nil }
        if let n = Int(parts[1]) { return n }
        guard let c = desktops.current else { return nil }
        return parts[1] == "h" ? c - 1 : parts[1] == "l" ? c + 1 : nil
    }

    // No space typed yet: filter by trigger (exact, then prefix) or title. After a space: only the exact trigger.
    var matches: [CommandDef] {
        let defs = self.defs().filter(\.enabled)
        let s = text.drop { $0 == " " }
        guard let head = s.split(separator: " ").first.map(String.init) else { return defs }
        if s.contains(" ") { return defs.filter { $0.trigger == head } }
        let exact = defs.filter { $0.trigger == head }
        let prefix = defs.filter { $0.trigger != head && $0.trigger.hasPrefix(head) }
        let title = defs.filter {
            !$0.trigger.hasPrefix(head) && (Action(rawValue: $0.id)?.title ?? "").localizedCaseInsensitiveContains(head)
        }
        return exact + prefix + title
    }

    func move(_ by: Int) {
        let n = matches.count
        if n > 0 { selected = (selected + by + n) % n }
    }

    // Enter: with arguments typed, run the text as-is. Otherwise act on the selected row:
    // commands that need an argument get their trigger filled in, the rest run.
    func enter() {
        let rows = matches
        guard !text.contains(" "), rows.indices.contains(selected) else { return submit(text) }
        let d = rows[selected]
        if Action(rawValue: d.id)?.argHint != nil { text = d.trigger + " " } else { submit(d.trigger) }
    }
}

struct PaletteView: View {
    @ObservedObject var model: Palette
    @ObservedObject var store = Store.shared
    @FocusState private var focused: Bool

    var body: some View {
        let rows = model.matches
        VStack(spacing: 10) {
            TextField("Type a command", text: $model.text)
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .focused($focused)
                .onSubmit { model.enter() }
                .onKeyPress(.downArrow) { model.move(1); return .handled }
                .onKeyPress(.upArrow) { model.move(-1); return .handled }
                .onKeyPress(.escape) { model.cancel(); return .handled }
                .padding(.horizontal, 24)
                .frame(height: 60)
                .glass(Capsule())
            if let cmd = model.desktopCommand, model.desktops.count > 0 {
                desktopStrip(cmd)
            }
            if !rows.isEmpty {
                VStack(spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, d in
                        row(d, selected: i == model.selected)
                            .onTapGesture { model.selected = i; model.enter() }
                    }
                }
                .padding(8)
                .glass(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        }
        .padding(20) // room for the shadow
        .frame(width: 600, height: 780, alignment: .top)
        .onChange(of: model.focusToken) { focused = true }
    }

    // Numbered tiles: current desktop outlined, typed target filled. Click a tile to go/move there.
    func desktopStrip(_ cmd: CommandDef) -> some View {
        let d = model.desktops
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            Text(d.current.map { "Desktop \($0) of \(d.count)" } ?? "\(d.count) desktops · full-screen app")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                ForEach(1...d.count, id: \.self) { n in
                    Text("\(n)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(n == model.desktopTarget ? Color.accentColor.opacity(0.7)
                                                             : Color.primary.opacity(0.08), in: shape)
                        .overlay(shape.strokeBorder(Color.primary.opacity(n == d.current ? 0.7 : 0), lineWidth: 1.5))
                        .contentShape(shape)
                        .onTapGesture { model.submit("\(cmd.trigger) \(n)") }
                }
            }
        }
        .padding(14)
        .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    func row(_ d: CommandDef, selected: Bool) -> some View {
        let a = Action(rawValue: d.id)
        return HStack(spacing: 16) {
            Image(systemName: a?.icon ?? "questionmark")
                .font(.system(size: 17))
                .frame(width: 24)
            Text(a?.title ?? d.id).font(.system(size: 15))
            Spacer()
            Text(d.trigger + (a?.argHint.map { " ‹\($0)›" } ?? ""))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(selected ? Color.primary.opacity(0.1) : .clear,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
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
