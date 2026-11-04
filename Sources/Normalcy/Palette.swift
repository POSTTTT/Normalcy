import SwiftUI

final class Palette: ObservableObject {
    @Published var text = "" { didSet { selected = 0 } }
    @Published var selected = 0
    @Published var focusToken = 0 // bumped on every show to refocus the field
    var submit: (String) -> Void = { _ in }
    var cancel: () -> Void = {}
    var defs: () -> [CommandDef] = { Store.shared.defs }
    @Published var desktops = Desktops()
    @Published var thumbs: [Int: NSImage] = [:] // space ID -> last snapshot
    @Published var wallpaper: NSImage? // stand-in for desktops not yet snapshotted

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
        switch Command.parse(text, defs()) {
        case .layout(let r): return r
        case .tabToWindow(let r): return r
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
        let exact = defs.filter { $0.trigger == head || Command.arrowAction(head)?.rawValue == $0.id }
        let prefix = defs.filter { $0.trigger != head && $0.trigger.hasPrefix(head) }
        let title = defs.filter {
            !$0.trigger.hasPrefix(head) && (Action(rawValue: $0.id)?.title ?? "").localizedCaseInsensitiveContains(head)
        }
        return exact + prefix + title
    }

    // Minimal style's key-cap blocks: one per word, plus a "␣" block per space if asked.
    static func keyBlocks(_ text: String, showSpaces: Bool) -> [String] {
        var out: [String] = [], word = ""
        for ch in text {
            if ch != " " { word.append(ch); continue }
            if !word.isEmpty { out.append(word); word = "" }
            if showSpaces { out.append("␣") }
        }
        if !word.isEmpty { out.append(word) }
        return out
    }

    // Arrow keys type ← ↓ ↑ →, which work like h j k l. Right after a command that takes a
    // direction (t, d, m) they add the space too, so "t" + ← becomes "t ←".
    func typeArrow(_ letter: String) {
        let head = text.trimmingCharacters(in: .whitespaces)
        let takesArg = defs().contains {
            $0.enabled && $0.trigger == head && Action(rawValue: $0.id)?.argHint != nil
        }
        text = takesArg && !text.hasSuffix(" ") ? head + " " + letter : text + letter
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
        if Action(rawValue: d.id)?.argRequired == true { text = d.trigger + " " } else { submit(d.trigger) }
    }
}

struct PaletteView: View {
    @ObservedObject var model: Palette
    @ObservedObject var store = Store.shared
    @FocusState private var focused: Bool

    var body: some View {
        let minimal = store.style == .minimal
        // The command bar style always sits near the top; the minimal style uses the chosen position.
        let position = minimal ? store.position : .top
        let alignment: Alignment = switch position {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        }
        GeometryReader { g in
            VStack(spacing: 10) {
                if minimal {
                    // Still receives the typing; only the letter squares below show it.
                    field.frame(width: 1, height: 1).opacity(0)
                    if position == .top { keys }
                    content
                    if position != .top { keys }
                } else {
                    field
                        .padding(.horizontal, 24)
                        .frame(height: 60)
                        .glass(Capsule())
                    content
                }
            }
            .padding(20) // room for the shadow
            .padding(.top, position == .top ? g.size.height * 0.15 : 0)
            .padding(.bottom, position == .bottom ? g.size.height * 0.08 : 0)
            .frame(width: g.size.width, height: g.size.height, alignment: alignment)
        }
        .onChange(of: model.focusToken) { focused = true }
    }

    var field: some View {
        TextField("Type a command", text: $model.text)
            .textFieldStyle(.plain)
            .font(.system(size: 22))
            .focused($focused)
            .onSubmit { model.enter() }
            .onKeyPress(phases: .down) { press in
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
                case .escape: model.cancel()
                default: return .ignored
                }
                return .handled
            }
    }

    @ViewBuilder var content: some View {
        let rows = model.matches
        if let cmd = model.desktopCommand, model.desktops.count > 0 {
            desktopStrip(cmd)
        }
        if store.showList, !rows.isEmpty {
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

    // Minimal style: one key-cap block per typed word, so "o Safari" shows [o] [Safari];
    // nothing when empty. shortcut: long input runs past the panel edge; wrap if that becomes a problem.
    var keys: some View {
        HStack(spacing: 8) {
            ForEach(Array(Palette.keyBlocks(model.text, showSpaces: store.showSpaces).enumerated()),
                    id: \.offset) { _, word in
                Text(Palette.spacedArrows(String(word)))
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 14)
                    .frame(minWidth: 44, minHeight: 44)
                    .glass(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // Mission Control-style thumbnails: target gets the accent border, current a faint one.
    // Click a thumbnail to go/move there.
    func desktopStrip(_ cmd: CommandDef) -> some View {
        let d = model.desktops
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return HStack(alignment: .top, spacing: 14) {
            ForEach(Array(d.ids.enumerated()), id: \.element) { i, id in
                let n = i + 1
                let isTarget = n == model.desktopTarget
                VStack(spacing: 6) {
                    Color.clear
                        .aspectRatio(16 / 10, contentMode: .fit)
                        .overlay { thumbnail(id) }
                        .clipShape(shape)
                        .overlay(shape.strokeBorder(isTarget ? Color.accentColor : Color.white.opacity(n == d.current ? 0.6 : 0.15),
                                                    lineWidth: isTarget ? 3 : 1))
                    Text("Desktop \(n)")
                        .font(.system(size: 12, weight: n == d.current ? .semibold : .regular))
                        .foregroundStyle(n == d.current ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: 160)
                .contentShape(Rectangle())
                .onTapGesture { model.submit("\(cmd.trigger) \(n)") }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder func thumbnail(_ id: Int) -> some View {
        if let img = model.thumbs[id] ?? model.wallpaper {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            Color.primary.opacity(0.08)
        }
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

// Full-screen, click-through layer under the bar: a translucent box where the window will go,
// like macOS's own tiling preview.
struct LayoutPreview: View {
    @ObservedObject var model: Palette

    var body: some View {
        GeometryReader { g in
            if let r = model.layoutPreview {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 2))
                    .frame(width: g.size.width * r.width - 16, height: g.size.height * r.height - 16)
                    .position(x: g.size.width * r.midX, y: g.size.height * r.midY)
                    .animation(.spring(duration: 0.25), value: r)
            }
        }
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
