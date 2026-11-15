import AppKit

let canvas: CGFloat = 1024
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func drawIcon() {
    let shape = NSBezierPath(roundedRect: body, xRadius: cornerRadius, yRadius: cornerRadius)
    drawDropShadow(for: shape)
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    drawBackground()
    drawGlow()
    drawStreaks()
    drawPlayButton()
    drawSheen()
    NSGraphicsContext.restoreGraphicsState()
    drawRim(for: shape)
}

func drawDropShadow(for shape: NSBezierPath) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0x15172E).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
}

func drawBackground() {
    let gradient = NSGradient(colors: [color(0x2B1B4F), color(0x15172E), color(0x0B0C1A)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)
    gradient?.draw(in: body, angle: -60)
}

func drawGlow() {
    let glow = NSGradient(colors: [color(0xFF6A88, 0.75), color(0xFF6A88, 0.22), color(0xFF6A88, 0)], atLocations: [0, 0.45, 1], colorSpace: .sRGB)
    glow?.draw(fromCenter: NSPoint(x: 560, y: 500), radius: 0, toCenter: NSPoint(x: 560, y: 500), radius: 430, options: [])
    let cool = NSGradient(colors: [color(0x7B5CFF, 0.55), color(0x7B5CFF, 0)], atLocations: nil, colorSpace: .sRGB)
    cool?.draw(fromCenter: NSPoint(x: 300, y: 760), radius: 0, toCenter: NSPoint(x: 300, y: 760), radius: 420, options: [])
}

func drawStreaks() {
    let streaks: [(y: CGFloat, length: CGFloat, alpha: CGFloat)] = [(612, 200, 0.5), (512, 270, 0.85), (412, 200, 0.5)]
    let rightEdge: CGFloat = 400
    for streak in streaks {
        let rect = NSRect(x: rightEdge - streak.length, y: streak.y - 22, width: streak.length, height: 44)
        let path = NSBezierPath(roundedRect: rect, xRadius: 22, yRadius: 22)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSGradient(colors: [color(0xFFFFFF, 0), color(0xFFFFFF, streak.alpha)], atLocations: nil, colorSpace: .sRGB)?.draw(in: rect, angle: 0)
        NSGraphicsContext.restoreGraphicsState()
    }
}

func drawPlayButton() {
    let triangle = roundedTriangle(tip: NSPoint(x: 800, y: 512), height: 400, cornerRadius: 64)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x2A0A2E, 0.55)
    shadow.shadowBlurRadius = 40
    shadow.shadowOffset = NSSize(width: 0, height: -16)
    shadow.set()
    color(0xFFFFFF).setFill()
    triangle.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    triangle.addClip()
    NSGradient(colors: [color(0xFFFFFF), color(0xFFE3EC)], atLocations: nil, colorSpace: .sRGB)?.draw(in: triangle.bounds, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
}

func roundedTriangle(tip: NSPoint, height: CGFloat, cornerRadius: CGFloat) -> NSBezierPath {
    let width = height * 0.9
    let top = NSPoint(x: tip.x - width, y: tip.y + height / 2)
    let bottom = NSPoint(x: tip.x - width, y: tip.y - height / 2)
    let corners = [top, tip, bottom]
    let path = NSBezierPath()
    for index in corners.indices {
        let current = corners[index]
        let previous = corners[(index + 2) % 3]
        let next = corners[(index + 1) % 3]
        let entry = point(from: current, toward: previous, distance: cornerRadius)
        let exit = point(from: current, toward: next, distance: cornerRadius)
        index == 0 ? path.move(to: entry) : path.line(to: entry)
        path.curve(to: exit, controlPoint1: current, controlPoint2: current)
    }
    path.close()
    return path
}

func point(from start: NSPoint, toward end: NSPoint, distance: CGFloat) -> NSPoint {
    let length = hypot(end.x - start.x, end.y - start.y)
    return NSPoint(x: start.x + (end.x - start.x) * distance / length, y: start.y + (end.y - start.y) * distance / length)
}

func drawSheen() {
    let upperHalf = NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2)
    NSGradient(colors: [color(0xFFFFFF, 0), color(0xFFFFFF, 0.08)], atLocations: nil, colorSpace: .sRGB)?.draw(in: upperHalf, angle: 90)
}

func drawRim(for shape: NSBezierPath) {
    color(0xFFFFFF, 0.10).setStroke()
    shape.lineWidth = 3
    shape.stroke()
}

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("Could not allocate the icon bitmap") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
drawIcon()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outputPath))
