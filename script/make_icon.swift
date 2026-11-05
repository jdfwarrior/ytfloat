import AppKit

// Deterministic vector artwork, rasterized only for the macOS app icon.
let output = CommandLine.arguments[1]
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 204, yRadius: 204)
NSGradient(starting: NSColor(calibratedRed: 0.19, green: 0.24, blue: 0.31, alpha: 1),
           ending: NSColor(calibratedRed: 0.035, green: 0.055, blue: 0.09, alpha: 1))!.draw(in: background, angle: -90)
let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.45); shadow.shadowBlurRadius = 34; shadow.shadowOffset = NSSize(width: 0, height: -22)
NSGraphicsContext.saveGraphicsState(); shadow.set()
let pane = NSBezierPath(roundedRect: NSRect(x: 200, y: 310, width: 624, height: 410), xRadius: 64, yRadius: 64)
NSColor(calibratedRed: 0.78, green: 0.84, blue: 0.92, alpha: 1).setFill(); pane.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: NSColor(calibratedRed: 0.9, green: 0.94, blue: 1, alpha: 1),
           ending: NSColor(calibratedRed: 0.48, green: 0.56, blue: 0.67, alpha: 1))!.draw(in: pane, angle: -80)
NSColor.white.withAlphaComponent(0.65).setStroke(); pane.lineWidth = 3; pane.stroke()
let video = NSBezierPath(roundedRect: NSRect(x: 224, y: 334, width: 576, height: 324), xRadius: 44, yRadius: 44)
NSGradient(starting: NSColor(calibratedRed: 0.99, green: 0.30, blue: 0.28, alpha: 1),
           ending: NSColor(calibratedRed: 0.78, green: 0.09, blue: 0.15, alpha: 1))!.draw(in: video, angle: -90)
for (x, color) in [(252.0, NSColor.systemRed), (276.0, .systemYellow), (300.0, .systemGreen)] {
    color.setFill(); NSBezierPath(ovalIn: NSRect(x: x, y: 680, width: 14, height: 14)).fill()
}
let play = NSBezierPath(); play.move(to: NSPoint(x: 460, y: 412)); play.line(to: NSPoint(x: 460, y: 580)); play.line(to: NSPoint(x: 602, y: 496)); play.close()
NSColor.white.setFill(); play.fill()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
