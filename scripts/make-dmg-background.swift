// Renders the DMG window background: swift scripts/make-dmg-background.swift out.png scale
import AppKit

let scale = Double(CommandLine.arguments[2]) ?? 1
let size = NSSize(width: 660 * scale, height: 400 * scale)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rect = NSRect(origin: .zero, size: size)
NSGradient(colors: [NSColor(white: 0.985, alpha: 1), NSColor(white: 0.92, alpha: 1)])!.draw(in: rect, angle: -90)

// The notch hanging from the top edge, like the app.
NSColor.black.setFill()
NSBezierPath(roundedRect: NSRect(x: (330 - 90) * scale, y: (400 - 34) * scale, width: 180 * scale, height: 60 * scale),
             xRadius: 16 * scale, yRadius: 16 * scale).fill()

func text(_ string: String, size font: Double, weight: NSFont.Weight, alpha: Double, y: Double) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: font * scale, weight: weight),
        .foregroundColor: NSColor(white: 0, alpha: alpha),
    ]
    let s = NSAttributedString(string: string, attributes: attrs)
    s.draw(at: NSPoint(x: (rect.width - s.size().width) / 2, y: y * scale))
}
text("Drag Nook to Applications", size: 17, weight: .semibold, alpha: 0.85, y: 312)
text("Then hover the notch or press ⌥⌘N", size: 12, weight: .regular, alpha: 0.5, y: 290)

// Arrow between the two icons (icons sit at y = 200 from the top, x = 180 and 480).
let accent = NSColor(red: 1.0, green: 0.62, blue: 0.24, alpha: 1)
accent.setStroke()
accent.setFill()
let arrow = NSBezierPath()
arrow.lineWidth = 3 * scale
arrow.lineCapStyle = .round
arrow.move(to: NSPoint(x: 280 * scale, y: 200 * scale))
arrow.line(to: NSPoint(x: 372 * scale, y: 200 * scale))
arrow.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 384 * scale, y: 200 * scale))
head.line(to: NSPoint(x: 368 * scale, y: 210 * scale))
head.line(to: NSPoint(x: 368 * scale, y: 190 * scale))
head.close()
head.fill()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
