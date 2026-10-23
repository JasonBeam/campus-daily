import AppKit
import Foundation

guard CommandLine.arguments.count == 6,
      let width = Int(CommandLine.arguments[2]),
      let height = Int(CommandLine.arguments[3]),
      let fontSize = Double(CommandLine.arguments[4]) else {
    fputs("usage: make-caption.swift OUTPUT WIDTH HEIGHT FONT_SIZE TEXT\n", stderr)
    exit(2)
}

let output = CommandLine.arguments[1]
let text = CommandLine.arguments[5]
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("unable to create bitmap\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(calibratedWhite: 0, alpha: 0.82).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph
]
let textRect = NSRect(
    x: 12,
    y: (height - Int(fontSize.rounded(.up))) / 2 - 1,
    width: width - 24,
    height: Int(fontSize.rounded(.up)) + 6
)
(text as NSString).draw(in: textRect, withAttributes: attributes)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fputs("unable to encode png\n", stderr)
    exit(1)
}
try data.write(to: URL(fileURLWithPath: output), options: .atomic)
