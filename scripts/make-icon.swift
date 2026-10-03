// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
import AppKit

func drawIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let scale = size / 1024
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: scale, y: scale)

        // Background: the standard macOS icon shape with a soft shadow.
        let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
        let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.shadowBlurRadius = 20
        shadow.set()
        NSColor.black.setFill()
        tilePath.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(
            starting: NSColor(calibratedRed: 0.98, green: 0.45, blue: 0.30, alpha: 1),
            ending: NSColor(calibratedRed: 0.80, green: 0.16, blue: 0.42, alpha: 1)
        )!.draw(in: tilePath, angle: -90)

        // A luggage-style tag, tilted, with rounded corners and a string hole.
        context.saveGState()
        context.translateBy(x: 512, y: 512)
        context.rotate(by: -.pi / 9)
        let w: CGFloat = 500, h: CGFloat = 320, taper: CGFloat = 120
        let outline = NSBezierPath()
        outline.move(to: NSPoint(x: -w / 2 + taper, y: h / 2))
        outline.line(to: NSPoint(x: w / 2, y: h / 2))
        outline.line(to: NSPoint(x: w / 2, y: -h / 2))
        outline.line(to: NSPoint(x: -w / 2 + taper, y: -h / 2))
        outline.line(to: NSPoint(x: -w / 2, y: 0))
        outline.close()
        let tag = outline.copy() as! NSBezierPath
        tag.append(NSBezierPath(ovalIn: NSRect(x: -w / 2 + 70, y: -36, width: 72, height: 72)))
        tag.windingRule = .evenOdd
        NSColor.white.setFill()
        tag.fill()
        // Stroking the outline (not the hole) rounds the corners.
        NSColor.white.setStroke()
        outline.lineWidth = 60
        outline.lineJoinStyle = .round
        outline.stroke()
        context.restoreGState()

        // A music note, upright, on the tag.
        let ink = NSColor(calibratedRed: 0.82, green: 0.20, blue: 0.40, alpha: 1)
        context.saveGState()
        context.translateBy(x: 555, y: 420)
        ink.setFill()
        ink.setStroke()
        let head = NSBezierPath(ovalIn: NSRect(x: -64, y: -42, width: 128, height: 84))
        var tilt = AffineTransform()
        tilt.rotate(byDegrees: 22)
        head.transform(using: tilt)
        head.fill()
        let stemX: CGFloat = 46
        NSBezierPath(rect: NSRect(x: stemX, y: 10, width: 28, height: 200)).fill()
        let flag = NSBezierPath()
        flag.move(to: NSPoint(x: stemX + 14, y: 198))
        flag.curve(to: NSPoint(x: stemX + 100, y: 75),
                   controlPoint1: NSPoint(x: stemX + 40, y: 150),
                   controlPoint2: NSPoint(x: stemX + 125, y: 140))
        flag.lineWidth = 26
        flag.lineCapStyle = .round
        flag.stroke()
        context.restoreGState()
        return true
    }
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let pixels = points * factor
        let image = drawIcon(size: CGFloat(pixels))
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        rep.size = NSSize(width: pixels, height: pixels)
        let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
print("Wrote \(output.path)")
