import AppKit

let outputPath = CommandLine.arguments[1]
let scale = Int(CommandLine.arguments[2])!
let size = NSSize(width: 540, height: 380)
let background = NSColor(srgbRed: 0xE4 / 255, green: 0xDE / 255, blue: 0xD1 / 255, alpha: 1)
let ink = NSColor(srgbRed: 0x2B / 255, green: 0x2E / 255, blue: 0x3F / 255, alpha: 1)

let arrow = [
    ".........#....",
    ".........##...",
    ".........###..",
    "#############.",
    "##############",
    "#############.",
    ".........###..",
    ".........##...",
    ".........#....",
]

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.shouldAntialias = false

background.setFill()
NSRect(origin: .zero, size: size).fill()

let cell: CGFloat = 5
let width = CGFloat(arrow[0].count) * cell, height = CGFloat(arrow.count) * cell
let left = size.width / 2 - width / 2, top = size.height - 170 + height / 2
ink.setFill()
for (row, line) in arrow.enumerated() {
    for (column, pixel) in line.enumerated() where pixel == "#" {
        NSRect(x: left + CGFloat(column) * cell, y: top - CGFloat(row + 1) * cell, width: cell, height: cell).fill()
    }
}

let caption = NSAttributedString(string: "Drag Flick into Applications", attributes: [
    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
    .foregroundColor: ink.withAlphaComponent(0.6),
])
NSGraphicsContext.current?.shouldAntialias = true
caption.draw(at: NSPoint(x: size.width / 2 - caption.size().width / 2, y: 60))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outputPath))
