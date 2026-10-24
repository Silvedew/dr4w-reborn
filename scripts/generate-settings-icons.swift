import AppKit
import Foundation

// Match the floating ball's white circle, blue accent, and native pencil symbol.
let output = URL(fileURLWithPath:CommandLine.arguments[1], isDirectory:true)
let style = try String(contentsOfFile:"Shared/RBIconStyle.h", encoding:.utf8)
let symbolName = style.components(separatedBy:"\"")[1]
let accent = NSColor(srgbRed:0, green:122.0/255, blue:1, alpha:1)
try FileManager.default.createDirectory(at:output, withIntermediateDirectories:true)

for scale in 1...3 {
    let pixels = 29 * scale
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil, pixelsWide:pixels, pixelsHigh:pixels,
        bitsPerSample:8, samplesPerPixel:4, hasAlpha:true, isPlanar:false,
        colorSpaceName:.deviceRGB, bytesPerRow:0, bitsPerPixel:0),
        let context = NSGraphicsContext(bitmapImageRep:bitmap) else { fatalError("Cannot create icon bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x:CGFloat(scale), y:CGFloat(scale))
    context.cgContext.clear(CGRect(x:0, y:0, width:29, height:29))
    let circle = NSBezierPath(ovalIn:NSRect(x:0.5, y:0.5, width:28, height:28))
    NSColor(white:1, alpha:0.94).setFill()
    circle.fill()
    accent.withAlphaComponent(0.2).setStroke()
    circle.lineWidth = 0.5
    circle.stroke()
    let config = NSImage.SymbolConfiguration(pointSize:29 * 24 / 56, weight:.semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors:[accent]))
    guard let pencil = NSImage(systemSymbolName:symbolName, accessibilityDescription:nil)?
        .withSymbolConfiguration(config) else { fatalError("Missing floating-ball symbol") }
    let size = pencil.size
    pencil.draw(in:NSRect(x:(29-size.width)/2, y:(29-size.height)/2, width:size.width, height:size.height))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using:.png, properties:[:]),
        bitmap.colorAt(x:pixels/2, y:pixels/2)!.alphaComponent > 0.5,
        bitmap.colorAt(x:0, y:0)!.alphaComponent < 0.1 else { fatalError("Invalid icon render") }
    let bluePixels = (0..<pixels).reduce(0) { count, x in
        count + (0..<pixels).filter { y in
            guard let color = bitmap.colorAt(x:x, y:y)?.usingColorSpace(.deviceRGB) else { return false }
            return color.alphaComponent > 0.5 && color.blueComponent > color.redComponent + 0.2
        }.count
    }
    precondition(bluePixels > 8 * scale * scale, "Missing blue pencil in rendered icon")
    let suffix = scale == 1 ? "" : "@\(scale)x"
    try data.write(to:output.appendingPathComponent("Dr4wReborn\(suffix).png"))
    print("Verified icon: \(pixels)x\(pixels) \(symbolName)")
}
