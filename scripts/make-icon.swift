import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  let scale = CGFloat(size) / 1024
  let transform = NSAffineTransform()
  transform.scale(by: scale)
  transform.concat()
  NSColor(red: 0.055, green: 0.43, blue: 0.36, alpha: 1).setFill()
  NSBezierPath(
    roundedRect: NSRect(x: 50, y: 50, width: 924, height: 924), xRadius: 205, yRadius: 205
  ).fill()
  NSColor.white.setFill()
  let left = NSBezierPath()
  left.move(to: NSPoint(x: 240, y: 730))
  left.curve(
    to: NSPoint(x: 476, y: 664), controlPoint1: NSPoint(x: 330, y: 744),
    controlPoint2: NSPoint(x: 434, y: 720))
  left.line(to: NSPoint(x: 476, y: 276))
  left.curve(
    to: NSPoint(x: 240, y: 342), controlPoint1: NSPoint(x: 398, y: 328),
    controlPoint2: NSPoint(x: 317, y: 356))
  left.close()
  left.fill()
  let right = NSBezierPath()
  right.move(to: NSPoint(x: 548, y: 664))
  right.curve(
    to: NSPoint(x: 784, y: 730), controlPoint1: NSPoint(x: 590, y: 720),
    controlPoint2: NSPoint(x: 694, y: 744))
  right.line(to: NSPoint(x: 784, y: 342))
  right.curve(
    to: NSPoint(x: 548, y: 276), controlPoint1: NSPoint(x: 707, y: 356),
    controlPoint2: NSPoint(x: 626, y: 328))
  right.close()
  right.fill()
  NSColor(red: 0.72, green: 0.87, blue: 0.79, alpha: 1).setFill()
  let bookmark = NSBezierPath()
  bookmark.move(to: NSPoint(x: 666, y: 730))
  bookmark.line(to: NSPoint(x: 716, y: 740))
  bookmark.line(to: NSPoint(x: 716, y: 566))
  bookmark.line(to: NSPoint(x: 691, y: 591))
  bookmark.line(to: NSPoint(x: 666, y: 566))
  bookmark.close()
  bookmark.fill()
  NSGraphicsContext.restoreGraphicsState()
  let png = bitmap.representation(using: .png, properties: [:])!
  let names: [Int: String] = [
    16: "icon_16x16.png", 32: "icon_16x16@2x.png", 64: "icon_32x32@2x.png", 128: "icon_128x128.png",
    256: "icon_128x128@2x.png", 512: "icon_256x256@2x.png", 1024: "icon_512x512@2x.png",
  ]
  try png.write(to: directory.appendingPathComponent(names[size]!))
  if size == 32 { try png.write(to: directory.appendingPathComponent("icon_32x32.png")) }
  if size == 256 { try png.write(to: directory.appendingPathComponent("icon_256x256.png")) }
  if size == 512 { try png.write(to: directory.appendingPathComponent("icon_512x512.png")) }
}
