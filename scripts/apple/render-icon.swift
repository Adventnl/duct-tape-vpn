// Original geometric tape mark shared by the native Mac and Flutter apps.
// Run with: swift scripts/apple/render-icon.swift OUTPUT.png
import AppKit
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
NSColor(calibratedRed: 0, green: 0.40, blue: 0.80, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200).fill()
func tape(angle: CGFloat, color: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: 512, yBy: 512)
    transform.rotate(byDegrees: angle)
    transform.concat()
    color.setFill()
    let path = NSBezierPath()
    let points: [NSPoint] = [
        .init(x: -310, y: -84), .init(x: 298, y: -84),
        .init(x: 310, y: -56), .init(x: 296, y: -28),
        .init(x: 310, y: 0), .init(x: 296, y: 28),
        .init(x: 310, y: 56), .init(x: 298, y: 84),
        .init(x: -310, y: 84), .init(x: -296, y: 56),
        .init(x: -310, y: 28), .init(x: -296, y: 0),
        .init(x: -310, y: -28), .init(x: -296, y: -56)
    ]
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.close(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
}
tape(angle: -36, color: NSColor(calibratedRed: 0.60, green: 0.79, blue: 1, alpha: 1))
tape(angle: 36, color: .white)
image.unlockFocus()
let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
