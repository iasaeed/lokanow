import AppKit
import Foundation

// Package the approved artwork into every required macOS app icon size.
// Run from the repository root: swift scripts/make-icon.swift Resources/Assets.xcassets/AppIcon.appiconset
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/AppIconSource.png")
guard let artwork = NSImage(contentsOf: source) else { fatalError("App icon source could not be loaded.") }
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
var images: [[String: String]] = []
for pointSize in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = pointSize * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        artwork.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(pointSize)x\(pointSize)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(filename))
        images.append(["idiom": "mac", "size": "\(pointSize)x\(pointSize)", "scale": "\(scale)x", "filename": filename])
    }
}
try JSONSerialization.data(withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys]).write(to: destination.appendingPathComponent("Contents.json"))
