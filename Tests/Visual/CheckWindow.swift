import AppKit
import CoreGraphics

// Capture only the running app's main window on the macOS CI machine.
let pid = Int(CommandLine.arguments[1])!
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let window = windows.first {
    guard $0[kCGWindowOwnerPID as String] as? Int == pid,
          let bounds = $0[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
    return (bounds["Width"] ?? 0) >= 490 && (bounds["Height"] ?? 0) >= 400
}
guard let id = window?[kCGWindowNumber as String] as? UInt32,
      let image = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution]) else {
    fatalError("Could not capture Daylist window")
}
let bitmap = NSBitmapImageRep(cgImage: image)
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))

// Each character has a distinctive prop: blue laptop, blue beret, purple
// planner. Count those colors within their actual locations in the window.
func pixels(x: Range<Double>, y: Range<Double>, purple: Bool = false) -> Int {
    var count = 0
    for row in Int(y.lowerBound * Double(bitmap.pixelsHigh))..<Int(y.upperBound * Double(bitmap.pixelsHigh)) {
        for col in Int(x.lowerBound * Double(bitmap.pixelsWide))..<Int(x.upperBound * Double(bitmap.pixelsWide)) {
            guard let c = bitmap.colorAt(x: col, y: row)?.usingColorSpace(.sRGB) else { continue }
            let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
            if b > r + 0.08 && (purple ? r > g + 0.045 : g > r + 0.05 && b > g + 0.05) { count += 1 }
        }
    }
    return count
}
let laptop = pixels(x: 0.03..<0.20, y: 0.02..<0.30)
let beret = pixels(x: 0.55..<0.93, y: 0.02..<0.30)
let planner = pixels(x: 0.35..<0.65, y: 0.34..<0.82, purple: true)
print("Visible artwork pixels: laptop \(laptop), artist \(beret), planner \(planner)")
guard min(laptop, beret, planner) > 12 else { fatalError("Missing illustration in rendered window") }
