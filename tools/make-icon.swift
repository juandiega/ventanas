// Generates Resources/Ventanas.iconset (to turn into .icns) and assets/social-preview.png
// Usage: swift tools/make-icon.swift
import AppKit

func render(width: Int, height: Int, _ draw: (CGContext, CGSize) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    draw(ctx.cgContext, CGSize(width: width, height: height))
    return rep
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

/// Draws the icon inside the square `rect`.
func drawIcon(_ c: CGContext, in rect: CGRect) {
    let s = rect.width
    // macOS icons leave ~10% of margin around the shape.
    let body = rect.insetBy(dx: s * 0.1, dy: s * 0.1)
    let radius = body.width * 0.225
    let shape = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Shadow + gradient background
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: color(0, 0, 0, 0.35))
    c.addPath(shape)
    c.setFillColor(color(60, 70, 200))
    c.fillPath()
    c.restoreGState()

    c.saveGState()
    c.addPath(shape)
    c.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(112, 92, 255), color(38, 132, 255)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.maxY),
                         end: CGPoint(x: body.maxX, y: body.minY), options: [])

    // Soft gloss on top
    let gloss = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(255, 255, 255, 0.22), color(255, 255, 255, 0)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(gloss, start: CGPoint(x: body.midX, y: body.maxY),
                         end: CGPoint(x: body.midX, y: body.midY), options: [])

    // Three list rows; the middle one is selected
    let rowW = body.width * 0.68
    let rowH = body.height * 0.15
    let gap = body.height * 0.065
    let totalH = rowH * 3 + gap * 2
    let startY = body.midY + totalH / 2 - rowH
    let x = body.midX - rowW / 2

    for index in 0..<3 {
        let selected = index == 1
        let rowRect = CGRect(x: x, y: startY - CGFloat(index) * (rowH + gap), width: rowW, height: rowH)
        let rowPath = CGPath(roundedRect: rowRect, cornerWidth: rowH * 0.32, cornerHeight: rowH * 0.32, transform: nil)

        c.saveGState()
        if selected {
            c.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.02, color: color(10, 20, 90, 0.35))
        }
        c.addPath(rowPath)
        c.setFillColor(selected ? color(255, 255, 255, 0.97) : color(255, 255, 255, 0.28))
        c.fillPath()
        c.restoreGState()

        // Dot (app icon) and line (title)
        let dot = rowH * 0.52
        let dotRect = CGRect(x: rowRect.minX + rowH * 0.3, y: rowRect.midY - dot / 2, width: dot, height: dot)
        c.setFillColor(selected ? color(88, 86, 240) : color(255, 255, 255, 0.55))
        c.fillEllipse(in: dotRect)

        let lineH = rowH * 0.2
        let lineW = rowW * (selected ? 0.5 : (index == 0 ? 0.42 : 0.34))
        let lineRect = CGRect(x: dotRect.maxX + rowH * 0.28, y: rowRect.midY - lineH / 2, width: lineW, height: lineH)
        c.addPath(CGPath(roundedRect: lineRect, cornerWidth: lineH / 2, cornerHeight: lineH / 2, transform: nil))
        c.setFillColor(selected ? color(60, 70, 200, 0.85) : color(255, 255, 255, 0.5))
        c.fillPath()
    }
    c.restoreGState()
}

func write(_ rep: NSBitmapImageRep, to path: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
try? fm.createDirectory(atPath: "Resources/Ventanas.iconset", withIntermediateDirectories: true)
try? fm.createDirectory(atPath: "assets", withIntermediateDirectories: true)

// App icon: every size of the .iconset
let sizes: [(name: String, px: Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
]
for (name, px) in sizes {
    let rep = render(width: px, height: px) { c, size in drawIcon(c, in: CGRect(origin: .zero, size: size)) }
    write(rep, to: "Resources/Ventanas.iconset/icon_\(name).png")
}

// GitHub social preview image (1280x640)
let social = render(width: 1280, height: 640) { c, size in
    let bg = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(24, 26, 48), color(14, 16, 30)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(bg, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
    drawIcon(c, in: CGRect(x: 90, y: 120, width: 400, height: 400))

    let title = NSAttributedString(string: "Ventanas", attributes: [
        .font: NSFont.systemFont(ofSize: 112, weight: .bold), .foregroundColor: NSColor.white])
    title.draw(at: NSPoint(x: 520, y: 330))
    let sub = NSAttributedString(string: "A list-style window switcher\nfor macOS · free and open source", attributes: [
        .font: NSFont.systemFont(ofSize: 34, weight: .regular),
        .foregroundColor: NSColor(white: 1, alpha: 0.7)])
    sub.draw(in: NSRect(x: 524, y: 200, width: 700, height: 110))
}
write(social, to: "assets/social-preview.png")
print("ok")
