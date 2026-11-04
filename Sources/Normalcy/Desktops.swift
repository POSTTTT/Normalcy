import AppKit
import ScreenCaptureKit

// Private CoreGraphics API: the only way to list Spaces. Read-only, works with SIP on.
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray
@_silgen_name("CGSCopySpacesForWindows") private func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ wids: CFArray) -> CFArray

struct Desktops: Equatable {
    var ids: [Int] = [] // space IDs of numbered desktops, in order
    var currentID: Int?

    var count: Int { ids.count }
    var current: Int? { currentID.flatMap { ids.firstIndex(of: $0) }.map { $0 + 1 } } // 1-based; nil on a full-screen app

    static func read() -> Desktops {
        parse(CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] ?? [])
    }

    // shortcut: first display only; with "Displays have separate Spaces" on, other monitors are ignored.
    static func parse(_ displays: [[String: Any]]) -> Desktops {
        guard let d = displays.first, let spaces = d["Spaces"] as? [[String: Any]] else { return Desktops() }
        // type 0 = normal desktop; full-screen apps get their own space but no desktop number.
        let ids = spaces.filter { ($0["type"] as? Int) == 0 }.compactMap { $0["ManagedSpaceID"] as? Int }
        return Desktops(ids: ids, currentID: (d["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int)
    }
}

enum Wallpaper {
    // Light/dark HEIC wallpapers hold both images; apple_desktop:apr metadata says which index is which.
    // shortcut: time-of-day (solar) wallpapers fall back to their first image.
    static func load(_ url: URL, dark: Bool) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var index = 0
        if let meta = CGImageSourceCopyMetadataAtIndex(src, 0, nil),
           let tag = CGImageMetadataCopyTagWithPath(meta, nil, "apple_desktop:apr" as CFString),
           let b64 = CGImageMetadataTagCopyValue(tag) as? String,
           let data = Data(base64Encoded: b64),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let i = plist[dark ? "d" : "l"] as? Int, i < CGImageSourceGetCount(src) {
            index = i
        }
        // Decode at thumbnail size; wallpapers are up to 6K.
        let opts = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 480] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(src, index, opts).map { NSImage(cgImage: $0, size: .zero) }
    }
}

enum Snapshot {
    // Thumbnail of the desktop currently on screen, minus the given windows (the bar and its
    // preview; Normalcy's Settings window stays in, it's a real window on that desktop).
    // Only the visible desktop can be captured, so other desktops show their last snapshot.
    // Needs Screen Recording permission; returns nil without it.
    // `bare` leaves out every app window too: just the wallpaper (and desktop icons), the
    // backdrop for rebuilt thumbnails of other desktops.
    @MainActor
    static func capture(excluding hidden: [NSWindow], bare: Bool = false) async -> NSImage? {
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first
        else { return nil }
        // Window numbers read after the await: the bar may only just have appeared.
        let ids = Set(hidden.map { CGWindowID($0.windowNumber) })
        let skip = content.windows.filter { ids.contains($0.windowID) || (bare && $0.windowLayer == 0) }
        let config = SCStreamConfiguration()
        config.width = 480
        config.height = 480 * display.height / max(display.width, 1)
        config.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: skip)
        guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }

    typealias Window = (id: CGWindowID, frame: CGRect, onScreen: Bool)

    // Windows of regular, visible apps on every desktop, front to back, by space ID, plus any
    // windows named in `also` (Normalcy's Settings; Normalcy itself is a menu bar app). Frames
    // are global, top-left origin. Background services' windows are left out. Closed windows an
    // app keeps around are listed too (on screen: false) and look the same as windows on other
    // desktops; the caller tells them apart.
    // shortcut: minimized windows may still be listed on their desktop; filter via AX if it shows.
    static func windowsBySpace(also: Set<CGWindowID> = []) -> [Int: [Window]] {
        let shown = Set(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isHidden }.map(\.processIdentifier))
        let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var out: [Int: [Window]] = [:]
        for w in info {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, shown.contains(pid) || also.contains(id),
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: b), frame.width > 50, frame.height > 50 else { continue }
            let spaces = CGSCopySpacesForWindows(CGSMainConnectionID(), 7, [id] as CFArray) as? [Int] ?? []
            let onScreen = w[kCGWindowIsOnscreen as String] as? Bool ?? false
            for s in spaces { out[s, default: []].append((id, frame, onScreen)) }
        }
        return out
    }

    // Stand-in thumbnail for a desktop that isn't on screen: the wallpaper with each of its
    // windows drawn where it sits (a plain box when a window can't be captured).
    @MainActor
    static func compose(_ windows: [Window], wallpaper: NSImage?) async -> NSImage? {
        guard let screen = NSScreen.screens.first?.frame else { return nil }
        let size = CGSize(width: 480, height: 480 * screen.height / screen.width)
        let s = size.width / screen.width
        let content = CGPreflightScreenCaptureAccess()
            ? try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) : nil
        var images: [CGImage?] = []
        for w in windows {
            var img: CGImage?
            if let sw = content?.windows.first(where: { $0.windowID == w.id }) {
                let c = SCStreamConfiguration()
                c.width = max(Int(w.frame.width * s * 2), 1)
                c.height = max(Int(w.frame.height * s * 2), 1)
                c.showsCursor = false
                img = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: sw), configuration: c)
            }
            images.append(img)
        }
        return NSImage(size: size, flipped: true) { rect in
            wallpaper?.draw(in: rect, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            for (w, img) in zip(windows, images).reversed() { // back to front
                let r = CGRect(x: w.frame.minX * s, y: w.frame.minY * s, width: w.frame.width * s, height: w.frame.height * s)
                if let img {
                    NSImage(cgImage: img, size: .zero).draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                } else {
                    NSColor.windowBackgroundColor.setFill()
                    NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill()
                }
            }
            return true
        }
    }

    // The app's front window: one showing on this desktop if any, else its largest elsewhere.
    // Needs Screen Recording permission; nil without it or when the app has no window.
    // shortcut: an app's kept-around closed windows can be picked when nothing is on screen.
    @MainActor
    static func appWindow(_ pid: pid_t) async -> NSImage? {
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return nil }
        let windows = content.windows.filter {
            $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 100 && $0.frame.height > 100
        }
        // The window list from CoreGraphics is in front-to-back order, so its first match is the front window.
        let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let frontID = onScreen.first {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        }?[kCGWindowNumber as String] as? CGWindowID
        guard let w = windows.first(where: { $0.windowID == frontID })
                ?? windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { return nil }
        let c = SCStreamConfiguration()
        c.width = 640
        c.height = max(Int(640 * w.frame.height / w.frame.width), 1)
        c.showsCursor = false
        guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: c)
        else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
}
