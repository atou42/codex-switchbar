import AppKit
import Foundation

// Generated at build time; no icon/font downloads or asset toolchain dependency.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    NSColor(calibratedRed: 0.10, green: 0.15, blue: 0.13, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 205, yRadius: 205).fill()
    func arrow(y: CGFloat, right: Bool, color: NSColor) {
        let path = NSBezierPath()
        path.lineWidth = 62; path.lineCapStyle = .round; path.lineJoinStyle = .round
        let left: CGFloat = 280, end: CGFloat = 744
        if right {
            path.move(to: NSPoint(x: left, y: y)); path.line(to: NSPoint(x: end, y: y))
            path.move(to: NSPoint(x: end - 135, y: y + 135)); path.line(to: NSPoint(x: end, y: y))
            path.line(to: NSPoint(x: end - 135, y: y - 135))
        } else {
            path.move(to: NSPoint(x: end, y: y)); path.line(to: NSPoint(x: left, y: y))
            path.move(to: NSPoint(x: left + 135, y: y + 135)); path.line(to: NSPoint(x: left, y: y))
            path.line(to: NSPoint(x: left + 135, y: y - 135))
        }
        color.setStroke(); path.stroke()
    }
    arrow(y: 666, right: true, color: NSColor(calibratedRed: 0.40, green: 0.84, blue: 0.67, alpha: 1))
    arrow(y: 358, right: false, color: NSColor(calibratedWhite: 0.93, alpha: 1))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    try render(pixels: size).write(to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(pixels: size * 2).write(to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
