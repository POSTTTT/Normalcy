// Draws the app icon: one white key cap with an N on a graphite tile.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let S: CGFloat = 1024
let out = "Sources/Normalcy/Resources/AppIcon.png"
let img = NSImage(size: NSSize(width: S, height: S), flipped: true) { _ in
    // macOS icon grid: an 824-point rounded tile centered on the 1024 canvas, room for its shadow.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.25, alpha: 1),
                        NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.11, alpha: 1)])!.draw(in: tile, angle: 90)

    // The key: a darker edge under a light face, like the command bar's key caps.
    let key = NSRect(x: 262, y: 250, width: 500, height: 480)
    let r = key.width * 0.16
    NSColor(white: 0.55, alpha: 1).setFill()
    NSBezierPath(roundedRect: key.offsetBy(dx: 0, dy: key.height * 0.07), xRadius: r, yRadius: r).fill()
    NSGradient(colors: [NSColor(white: 0.95, alpha: 1), NSColor(white: 0.88, alpha: 1)])!
        .draw(in: NSBezierPath(roundedRect: key, xRadius: r, yRadius: r), angle: -90)
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 330, weight: .bold),
                                                .foregroundColor: NSColor(white: 0.12, alpha: 1)]
    let size = ("N" as NSString).size(withAttributes: attrs)
    ("N" as NSString).draw(at: NSPoint(x: key.midX - size.width / 2, y: key.midY - size.height / 2 - 13), withAttributes: attrs)
    return true
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(in: NSRect(x: 0, y: 0, width: S, height: S))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote", out)
