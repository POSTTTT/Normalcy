import CoreGraphics

// Private CoreGraphics API: the only way to list Spaces. Read-only, works with SIP on.
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray

struct Desktops: Equatable {
    var count = 0
    var current: Int? // 1-based; nil while a full-screen app is showing

    static func read() -> Desktops {
        parse(CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] ?? [])
    }

    // shortcut: first display only; with "Displays have separate Spaces" on, other monitors are ignored.
    static func parse(_ displays: [[String: Any]]) -> Desktops {
        guard let d = displays.first, let spaces = d["Spaces"] as? [[String: Any]] else { return Desktops() }
        // type 0 = normal desktop; full-screen apps get their own space but no desktop number.
        let ids = spaces.filter { ($0["type"] as? Int) == 0 }.compactMap { $0["ManagedSpaceID"] as? Int }
        let cur = (d["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
        return Desktops(count: ids.count, current: cur.flatMap { ids.firstIndex(of: $0) }.map { $0 + 1 })
    }
}
