import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for density in [1, 2] {
        let pixels = size * density
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let rect = CGRect(x: 60, y: 60, width: 904, height: 904)
        NSColor(calibratedRed: 0.07, green: 0.10, blue: 0.13, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 215, yRadius: 215).fill()
        let mint = NSColor(calibratedRed: 0.36, green: 0.86, blue: 0.71, alpha: 1)
        func line(_ points: [CGPoint], _ color: NSColor, _ width: CGFloat) {
            let path = NSBezierPath()
            path.move(to: points[0])
            for p in points.dropFirst() { path.line(to: p) }
            path.lineWidth = width
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            color.setStroke(); path.stroke()
        }
        line([CGPoint(x: 270, y: 360), CGPoint(x: 270, y: 635), CGPoint(x: 512, y: 770), CGPoint(x: 754, y: 635), CGPoint(x: 754, y: 360), CGPoint(x: 512, y: 225), CGPoint(x: 270, y: 360)], mint, 29)
        line([CGPoint(x: 270, y: 635), CGPoint(x: 512, y: 495), CGPoint(x: 754, y: 635)], mint, 29)
        line([CGPoint(x: 512, y: 495), CGPoint(x: 512, y: 225)], mint, 29)
        NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.19, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: 640, y: 200, width: 220, height: 220)).fill()
        line([CGPoint(x: 750, y: 253), CGPoint(x: 750, y: 367)], mint, 25)
        line([CGPoint(x: 693, y: 310), CGPoint(x: 807, y: 310)], mint, 25)
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = density == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
