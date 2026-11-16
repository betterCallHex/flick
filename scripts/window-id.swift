import CoreGraphics

let owner = CommandLine.arguments[1]
let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let match = windows.first { window in
    window[kCGWindowOwnerName as String] as? String == owner
        && window[kCGWindowLayer as String] as? Int == 0
        && (window[kCGWindowBounds as String] as? [String: Double])?["Height"] ?? 0 > 100
}
guard let id = match?[kCGWindowNumber as String] as? Int else { exit(1) }
print(id)
