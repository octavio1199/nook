// Renders a 1024x1024 app icon PNG: swift scripts/make-icon.swift out.png
import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let plate = NSBezierPath(roundedRect: rect.insetBy(dx: 40, dy: 40), xRadius: 200, yRadius: 200)
NSGradient(colors: [NSColor(red: 1.0, green: 0.62, blue: 0.24, alpha: 1), NSColor(red: 0.98, green: 0.36, blue: 0.36, alpha: 1)])!
    .draw(in: plate, angle: -60)
// The notch, hanging from the top edge.
let notch = NSBezierPath(roundedRect: NSRect(x: 292, y: 560, width: 440, height: 424), xRadius: 90, yRadius: 90)
NSColor.black.setFill()
notch.fill()
NSColor.white.withAlphaComponent(0.92).setFill()
for (i, w) in [300.0, 220.0, 260.0].enumerated() {
    NSBezierPath(roundedRect: NSRect(x: 362, y: 860 - Double(i) * 90, width: w, height: 36), xRadius: 18, yRadius: 18).fill()
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
