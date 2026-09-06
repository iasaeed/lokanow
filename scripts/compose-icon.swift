import AppKit
import Foundation
// Apple Xcode 26 artwork, retrieved from the official App Store CDN.
// Badge coordinates preserve the approved preview relative to the original blue shape.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("Resources/XcodeIconOriginal.png")
let original = NSImage(contentsOf: source)!
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
original.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), from: .zero, operation: .copy, fraction: 1)
let scale = CGFloat(824.0 / 174.0)
let offset = CGFloat(100) - CGFloat(9) * scale
NSGraphicsContext.current!.cgContext.translateBy(x: offset, y: offset)
NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 28, weight: .medium), .foregroundColor: NSColor.white]
("A" as NSString).draw(at: NSPoint(x: 29, y: 127), withAttributes: attributes)
("あ" as NSString).draw(at: NSPoint(x: 52, y: 102), withAttributes: [.font: NSFont.systemFont(ofSize: 25, weight: .medium), .foregroundColor: NSColor.white])
let arrows = NSBezierPath()
arrows.lineWidth = 2
arrows.move(to: NSPoint(x: 53, y: 143)); arrows.curve(to: NSPoint(x: 67, y: 131), controlPoint1: NSPoint(x: 63, y: 143), controlPoint2: NSPoint(x: 67, y: 140))
arrows.move(to: NSPoint(x: 62, y: 136)); arrows.line(to: NSPoint(x: 67, y: 131)); arrows.line(to: NSPoint(x: 71, y: 137))
arrows.move(to: NSPoint(x: 49, y: 114)); arrows.curve(to: NSPoint(x: 35, y: 126), controlPoint1: NSPoint(x: 39, y: 114), controlPoint2: NSPoint(x: 35, y: 117))
arrows.move(to: NSPoint(x: 31, y: 120)); arrows.line(to: NSPoint(x: 35, y: 126)); arrows.line(to: NSPoint(x: 40, y: 121))
NSColor.white.setStroke(); arrows.stroke()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("Resources/AppIconSource.png"))
