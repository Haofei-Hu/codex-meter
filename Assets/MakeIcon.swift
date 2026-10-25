import AppKit

let destination = CommandLine.arguments[1]
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.shouldAntialias = true
let tile = NSBezierPath(roundedRect: NSRect(x: 82, y: 82, width: 860, height: 860), xRadius: 192, yRadius: 192)
NSColor(calibratedRed: 0.075, green: 0.10, blue: 0.115, alpha: 1).setFill()
tile.fill()
let center = NSPoint(x: 512, y: 512)
let radius: CGFloat = 254
let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
track.lineWidth = 72
NSColor(calibratedRed: 0.17, green: 0.23, blue: 0.25, alpha: 1).setStroke()
track.stroke()
let progress = NSBezierPath()
progress.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: -195, clockwise: true)
progress.lineWidth = 72
progress.lineCapStyle = .round
NSColor(calibratedRed: 0.42, green: 0.92, blue: 0.77, alpha: 1).setStroke()
progress.stroke()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
