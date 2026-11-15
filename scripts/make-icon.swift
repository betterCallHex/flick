import AppKit

struct Cell: Hashable {
    let x: Int
    let y: Int

    func offset(_ dx: Int, _ dy: Int) -> Cell { Cell(x: x + dx, y: y + dy) }

    var neighbors: [Cell] { [offset(1, 0), offset(-1, 0), offset(0, 1), offset(0, -1)] }

    var ring: [Cell] { neighbors + [offset(1, 1), offset(1, -1), offset(-1, 1), offset(-1, -1)] }
}

enum Palette {
    static let ink = rgb(0x12_0526)
    static let shadow = rgb(0x2A_0B4D)
    static let sky = [rgb(0x1E_0B45), rgb(0x3D_1273), rgb(0x7B_1FA2), rgb(0xD6_2F7F), rgb(0xFF_7A3D)]
    static let star = rgb(0xFF_F4D6)
    static let playLight = rgb(0xFF_FFFF)
    static let playBase = rgb(0xFF_EBC2)
    static let playShade = rgb(0xFF_B35C)
    static let streak = rgb(0x4D_F3FF)
    static let streakFaint = rgb(0x2A_9DC4)

    static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

let gridSize = 32
let canvas = 1024
let cellSize = canvas / gridSize
let bodyRange = 3...28
let appleTemplate = NSRect(x: 100, y: 100, width: 824, height: 824)
let appleTemplateCornerRadius: CGFloat = 185
let bayer4x4: [[Double]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

func isInBody(_ cell: Cell) -> Bool {
    bodyRange.contains(cell.x) && bodyRange.contains(cell.y)
}

func isInPlayButton(_ cell: Cell) -> Bool {
    let leftEdge = 13
    let halfHeight = 7.0
    let length = 11.0
    let distanceFromMiddle = abs(Double(cell.y) + 0.5 - 16)
    let width = (1 - distanceFromMiddle / halfHeight) * length
    return cell.x >= leftEdge && Double(cell.x - leftEdge) + 0.5 <= width
}

func skyColor(_ cell: Cell) -> NSColor {
    let progress = Double(cell.y - bodyRange.lowerBound) / Double(bodyRange.count - 1)
    let band = progress * Double(Palette.sky.count - 1)
    let lower = Int(band)
    let threshold = (bayer4x4[cell.y % 4][cell.x % 4] + 0.5) / 16
    let index = band - Double(lower) > threshold ? lower + 1 : lower
    return Palette.sky[min(index, Palette.sky.count - 1)]
}

func streakColor(_ cell: Cell) -> NSColor? {
    let rows: [Int: (start: Int, solidFrom: Int)] = [12: (7, 9), 15: (5, 8), 16: (5, 8), 19: (7, 9)]
    let streakEnd = 10
    guard let row = rows[cell.y], (row.start...streakEnd).contains(cell.x) else { return nil }
    if cell.x >= row.solidFrom { return Palette.streak }
    return (cell.x - row.start).isMultiple(of: 2) ? Palette.streakFaint : nil
}

func playColor(_ cell: Cell) -> NSColor {
    if !isInPlayButton(cell.offset(0, -1)) || !isInPlayButton(cell.offset(-1, 0)) { return Palette.playLight }
    if !isInPlayButton(cell.offset(0, 1)) || !isInPlayButton(cell.offset(1, 0)) { return Palette.playShade }
    return Palette.playBase
}

func color(of cell: Cell) -> NSColor? {
    guard isInBody(cell) else { return nil }
    if isInPlayButton(cell) { return playColor(cell) }
    if cell.ring.contains(where: isInPlayButton) { return Palette.ink }
    if isInPlayButton(cell.offset(-2, -2)) { return Palette.shadow }
    if let streak = streakColor(cell) { return streak }
    let stars: Set<Cell> = [Cell(x: 8, y: 6), Cell(x: 19, y: 5), Cell(x: 25, y: 8), Cell(x: 6, y: 9), Cell(x: 14, y: 7)]
    if stars.contains(cell) { return Palette.star }
    return skyColor(cell)
}

func drawIcon() {
    NSBezierPath(roundedRect: appleTemplate, xRadius: appleTemplateCornerRadius, yRadius: appleTemplateCornerRadius).addClip()
    for y in 0..<gridSize {
        for x in 0..<gridSize {
            guard let fill = color(of: Cell(x: x, y: y)) else { continue }
            fill.setFill()
            NSRect(x: x * cellSize, y: canvas - (y + 1) * cellSize, width: cellSize, height: cellSize).fill()
        }
    }
}

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("Could not allocate the icon bitmap") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
drawIcon()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outputPath))
