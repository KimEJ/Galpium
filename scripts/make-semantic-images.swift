import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
  fatalError("Usage: swift scripts/make-semantic-images.swift <output-directory>")
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let dimension = 640
let canvas = CGRect(x: 0, y: 0, width: dimension, height: dimension)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
  CGColor(red: red, green: green, blue: blue, alpha: 1)
}

func label(_ text: String, context: CGContext) {
  let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 58, nil)
  let line = CTLineCreateWithAttributedString(
    NSAttributedString(
      string: text,
      attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(0.10, 0.14, 0.20),
      ]))
  context.textPosition = CGPoint(
    x: (CGFloat(dimension) - CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))) / 2,
    y: 55)
  CTLineDraw(line, context)
}

func makeImage(_ draw: (CGContext) -> Void) -> CGImage {
  let context = CGContext(
    data: nil, width: dimension, height: dimension, bitsPerComponent: 8, bytesPerRow: dimension * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
  context.setFillColor(color(0.98, 0.98, 0.96))
  context.fill(canvas)
  draw(context)
  return context.makeImage()!
}

let apple = makeImage { context in
  // A stem and leaf distinguish the silhouette from an ordinary red circle.
  context.setStrokeColor(color(0.32, 0.18, 0.07))
  context.setLineWidth(22)
  context.setLineCap(.round)
  context.move(to: CGPoint(x: 316, y: 437))
  context.addQuadCurve(to: CGPoint(x: 340, y: 532), control: CGPoint(x: 310, y: 490))
  context.strokePath()

  let leaf = CGMutablePath()
  leaf.move(to: CGPoint(x: 331, y: 499))
  leaf.addCurve(
    to: CGPoint(x: 446, y: 552), control1: CGPoint(x: 349, y: 558),
    control2: CGPoint(x: 404, y: 571))
  leaf.addCurve(
    to: CGPoint(x: 331, y: 499), control1: CGPoint(x: 437, y: 498),
    control2: CGPoint(x: 378, y: 476))
  leaf.closeSubpath()
  context.addPath(leaf)
  context.setFillColor(color(0.17, 0.58, 0.17))
  context.fillPath()

  let fruit = CGMutablePath()
  fruit.move(to: CGPoint(x: 320, y: 435))
  fruit.addCurve(
    to: CGPoint(x: 146, y: 405), control1: CGPoint(x: 242, y: 501),
    control2: CGPoint(x: 154, y: 474))
  fruit.addCurve(
    to: CGPoint(x: 222, y: 168), control1: CGPoint(x: 93, y: 325),
    control2: CGPoint(x: 149, y: 191))
  fruit.addCurve(
    to: CGPoint(x: 320, y: 171), control1: CGPoint(x: 260, y: 150),
    control2: CGPoint(x: 290, y: 170))
  fruit.addCurve(
    to: CGPoint(x: 418, y: 168), control1: CGPoint(x: 350, y: 170),
    control2: CGPoint(x: 380, y: 150))
  fruit.addCurve(
    to: CGPoint(x: 494, y: 405), control1: CGPoint(x: 491, y: 191),
    control2: CGPoint(x: 547, y: 325))
  fruit.addCurve(
    to: CGPoint(x: 320, y: 435), control1: CGPoint(x: 486, y: 474),
    control2: CGPoint(x: 398, y: 501))
  fruit.closeSubpath()
  context.addPath(fruit)
  context.setFillColor(color(0.88, 0.08, 0.10))
  context.fillPath()

  context.setFillColor(color(0.99, 0.40, 0.38))
  context.fillEllipse(in: CGRect(x: 178, y: 330, width: 35, height: 76))
  label("APPLE", context: context)
}

let bicycle = makeImage { context in
  let rear = CGPoint(x: 165, y: 248)
  let front = CGPoint(x: 479, y: 248)
  let crank = CGPoint(x: 322, y: 248)
  let saddleBase = CGPoint(x: 270, y: 391)
  let handleBase = CGPoint(x: 409, y: 391)

  context.setStrokeColor(color(0.12, 0.15, 0.19))
  context.setLineWidth(15)
  for center in [rear, front] {
    context.strokeEllipse(in: CGRect(x: center.x - 104, y: center.y - 104, width: 208, height: 208))
    context.setLineWidth(3)
    for index in 0..<12 {
      let angle = CGFloat(index) * .pi / 6
      context.move(to: center)
      context.addLine(to: CGPoint(x: center.x + cos(angle) * 96, y: center.y + sin(angle) * 96))
      context.strokePath()
    }
    context.setLineWidth(15)
  }

  context.setStrokeColor(color(0.04, 0.34, 0.88))
  context.setLineWidth(18)
  context.setLineJoin(.round)
  context.setLineCap(.round)
  context.move(to: rear)
  for point in [saddleBase, crank, rear] { context.addLine(to: point) }
  context.move(to: saddleBase)
  for point in [handleBase, crank] { context.addLine(to: point) }
  context.move(to: front)
  context.addLine(to: CGPoint(x: 397, y: 430))
  context.move(to: saddleBase)
  context.addLine(to: CGPoint(x: 257, y: 426))
  context.strokePath()

  context.setStrokeColor(color(0.12, 0.15, 0.19))
  context.setLineWidth(14)
  context.move(to: CGPoint(x: 226, y: 428))
  context.addLine(to: CGPoint(x: 290, y: 428))
  context.move(to: CGPoint(x: 397, y: 430))
  for point in [CGPoint(x: 418, y: 455), CGPoint(x: 453, y: 455)] { context.addLine(to: point) }
  context.move(to: crank)
  for point in [CGPoint(x: 347, y: 220), CGPoint(x: 371, y: 220)] { context.addLine(to: point) }
  context.strokePath()
  context.setFillColor(color(0.12, 0.15, 0.19))
  context.fillEllipse(in: CGRect(x: crank.x - 13, y: crank.y - 13, width: 26, height: 26))
  label("BICYCLE", context: context)
}

for (name, image) in [("asset-a.png", apple), ("asset-b.png", bicycle)] {
  let destination = CGImageDestinationCreateWithURL(
    directory.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("PNG export failed") }
}

func jpegBytes(_ image: CGImage) -> Data {
  let data = NSMutableData()
  let destination = CGImageDestinationCreateWithData(
    data, UTType.jpeg.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(
    destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
  guard CGImageDestinationFinalize(destination) else { fatalError("JPEG export failed") }
  return data as Data
}

// Only image XObjects are painted on these pages. A minimal PDF writer avoids
// generated timestamps or identifiers, keeping the fixture bytes reproducible.
var pdf = Data("%PDF-1.4\n".utf8)
var offsets = [0]
func object(_ id: Int, _ body: Data) {
  precondition(id == offsets.count)
  offsets.append(pdf.count)
  pdf.append(Data("\(id) 0 obj\n".utf8))
  pdf.append(body)
  pdf.append(Data("\nendobj\n".utf8))
}
func stream(_ dictionary: String, _ bytes: Data) -> Data {
  var result = Data("<< \(dictionary) /Length \(bytes.count) >>\nstream\n".utf8)
  result.append(bytes)
  result.append(Data("\nendstream".utf8))
  return result
}
object(1, Data("<< /Type /Catalog /Pages 2 0 R >>".utf8))
object(2, Data("<< /Type /Pages /Count 2 /Kids [3 0 R 6 0 R] >>".utf8))
for (index, image) in [apple, bicycle].enumerated() {
  let page = 3 + index * 3
  object(
    page,
    Data(
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 640 640] /Resources << /XObject << /Im0 \(page + 2) 0 R >> >> /Contents \(page + 1) 0 R >>"
        .utf8))
  object(page + 1, stream("", Data("q 640 0 0 640 0 0 cm /Im0 Do Q".utf8)))
  object(
    page + 2,
    stream(
      "/Type /XObject /Subtype /Image /Width 640 /Height 640 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode",
      jpegBytes(image)))
}
let xref = pdf.count
pdf.append(Data("xref\n0 \(offsets.count)\n0000000000 65535 f \n".utf8))
for offset in offsets.dropFirst() {
  pdf.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
}
pdf.append(Data("trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
let pdfURL = directory.appendingPathComponent("asset-c.pdf")
try pdf.write(to: pdfURL)
precondition(pdf.count < 2 * 1024 * 1024, "PDF must fit the material upload limit")
guard let document = PDFDocument(url: pdfURL), document.pageCount == 2 else {
  fatalError("PDF must contain exactly two pages")
}
for index in 0..<document.pageCount {
  precondition(document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
}
print("Created asset-a.png, asset-b.png, and image-only asset-c.pdf (2 pages)")
