import AppKit
import ScreenCaptureKit

// Private CoreGraphics API: the only way to list Spaces. Read-only, works with SIP on.
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray

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
    // Thumbnail of the desktop currently on screen, minus Normalcy's own windows.
    // Only the visible desktop can be captured, so other desktops show their last snapshot.
    // Needs Screen Recording permission; returns nil without it.
    static func capture() async -> NSImage? {
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first
        else { return nil }
        let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let config = SCStreamConfiguration()
        config.width = 480
        config.height = 480 * display.height / max(display.width, 1)
        config.showsCursor = false
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
}
