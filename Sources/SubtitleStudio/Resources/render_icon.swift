import AppKit
import Foundation
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.shouldAntialias = true
NSColor(calibratedRed: 32/255.0, green: 167/255.0, blue: 104/255.0, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 184, yRadius: 184).fill()
NSColor.white.setStroke()
let screen = NSBezierPath(roundedRect: NSRect(x: 232, y: 306, width: 560, height: 412), xRadius: 62, yRadius: 62)
screen.lineWidth = 44
screen.stroke()
NSColor.white.setFill()
for y in [472, 388] {
    NSBezierPath(roundedRect: NSRect(x: 318, y: y, width: 388, height: 44), xRadius: 22, yRadius: 22).fill()
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
