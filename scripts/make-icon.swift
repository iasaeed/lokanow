import AppKit
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
var images: [[String: String]] = []
for pointSize in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = pointSize * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let outer = NSBezierPath(roundedRect: NSRect(x: 58, y: 58, width: 908, height: 908), xRadius: 208, yRadius: 208)
        NSColor(calibratedRed: 0.12, green: 0.31, blue: 0.28, alpha: 1).setFill(); outer.fill()
        NSColor(calibratedRed: 0.9, green: 0.94, blue: 0.82, alpha: 1).setFill()
        let bubble = NSBezierPath(roundedRect: NSRect(x: 211, y: 294, width: 600, height: 476), xRadius: 100, yRadius: 100); bubble.fill()
        let tail = NSBezierPath(); tail.move(to: NSPoint(x: 300, y: 365)); tail.line(to: NSPoint(x: 300, y: 206)); tail.line(to: NSPoint(x: 467, y: 334)); tail.close(); tail.fill()
        NSColor(calibratedRed: 0.12, green: 0.31, blue: 0.28, alpha: 1).setStroke()
        let globe = NSBezierPath(ovalIn: NSRect(x: 370, y: 391, width: 280, height: 280)); globe.lineWidth = 22; globe.stroke()
        let ellipse = NSBezierPath(ovalIn: NSRect(x: 455, y: 391, width: 110, height: 280)); ellipse.lineWidth = 18; ellipse.stroke()
        let line = NSBezierPath(); line.move(to: NSPoint(x: 380, y: 531)); line.line(to: NSPoint(x: 640, y: 531)); line.lineWidth = 18; line.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(pointSize)x\(pointSize)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(filename))
        images.append(["idiom": "mac", "size": "\(pointSize)x\(pointSize)", "scale": "\(scale)x", "filename": filename])
    }
}
try JSONSerialization.data(withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("Contents.json"))
