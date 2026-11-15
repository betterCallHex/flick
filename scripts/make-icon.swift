import AppKit

struct Cell: Hashable {
    let x: Int
    let y: Int
}

enum Palette {
    static let skyTop = rgb(0x2B_2E3F)
    static let skyBottom = rgb(0x35_3A4E)
    static let play = rgb(0xE4_DED1)
    static let playShade = rgb(0xC8_C1B2)

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
let appleTemplate = NSRect(x: 100, y: 100, width: 824, height: 824)
let appleTemplateCornerRadius: CGFloat = 185
let playRows = 9...22
let playColumns = 10...21
let bayer4x4: [[Double]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

func isInPlayButton(_ cell: Cell) -> Bool {
    guard playRows.contains(cell.y) else { return false }
    let middle = Double(playRows.lowerBound + playRows.upperBound + 1) / 2
    let rowsFromMiddle = abs(Double(cell.y) + 0.5 - middle) - 0.5
    let taper = rowsFromMiddle / Double(playRows.count / 2)
    let width = Int((Double(playColumns.count) * (1 - taper)).rounded())
    return (playColumns.lowerBound..<playColumns.lowerBound + width).contains(cell.x)
}

func skyColor(_ cell: Cell) -> NSColor {
    let progress = Double(cell.y) / Double(gridSize - 1)
    let threshold = (bayer4x4[cell.y % 4][cell.x % 4] + 0.5) / 16
    return progress > threshold ? Palette.skyBottom : Palette.skyTop
}

func color(of cell: Cell) -> NSColor {
    guard isInPlayButton(cell) else { return skyColor(cell) }
    let isLowerEdge = !isInPlayButton(Cell(x: cell.x, y: cell.y + 1)) || !isInPlayButton(Cell(x: cell.x + 1, y: cell.y))
    return isLowerEdge && cell.y >= 16 ? Palette.playShade : Palette.play
}

func drawIcon() {
    NSBezierPath(roundedRect: appleTemplate, xRadius: appleTemplateCornerRadius, yRadius: appleTemplateCornerRadius).addClip()
    for y in 0..<gridSize {
        for x in 0..<gridSize {
            color(of: Cell(x: x, y: y)).setFill()
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
