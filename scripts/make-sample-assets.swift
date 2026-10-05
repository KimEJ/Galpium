import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func draw(_ text: String, x: CGFloat, y: CGFloat, context: CGContext, size: CGFloat = 16) {
  context.textPosition = CGPoint(x: x, y: y)
  let font = CTFontCreateWithName("AppleSDGothicNeo-Regular" as CFString, size, nil)
  let line = CTLineCreateWithAttributedString(
    NSAttributedString(
      string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
  CTLineDraw(line, context)
}
let data = NSMutableData()
var box = CGRect(x: 0, y: 0, width: 600, height: 800)
let pdf = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
let pages = [
  [
    "샘플 · 개인 위키 운영 메모", "문서와 자료는 서로 연결할 수 있습니다.", "직접 작성한 문서는 자료 없이 저장할 수 있습니다.",
    "연결된 자료와 원문 인용은 별도로 관리합니다.",
  ],
  [
    "Sample · Backups and citations",
    "Backups preserve pages, original materials, and citation evidence.",
    "A citation records its source version and page location.",
    "Keep original files when a historical revision still references them.",
  ],
  [
    "サンプル · 原文と引用", "引用には資料、原文の版、ページと引用文を記録します。", "検索結果は候補であり、内容の正しさを保証しません。",
    "同じファイルの異なる出典は別々に保持します。",
  ],
]
for lines in pages {
  pdf.beginPDFPage(nil)
  for (index, line) in lines.enumerated() {
    draw(line, x: 40, y: CGFloat(730 - index * 52), context: pdf, size: index == 0 ? 24 : 16)
  }
  pdf.endPDFPage()
}
pdf.closePDF()
try (data as Data).write(to: directory.appendingPathComponent("샘플-위키-운영안내.pdf"))
let imageContext = CGContext(
  data: nil, width: 960, height: 540, bitsPerComponent: 8, bytesPerRow: 0,
  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
imageContext.setFillColor(CGColor(red: 0.96, green: 0.98, blue: 0.97, alpha: 1))
imageContext.fill(CGRect(x: 0, y: 0, width: 960, height: 540))
imageContext.setFillColor(CGColor(red: 0.04, green: 0.4, blue: 0.32, alpha: 1))
for (index, title) in ["Materials", "Wiki pages", "Footnotes"].enumerated() {
  imageContext.fill(CGRect(x: 70 + index * 290, y: 170, width: 240, height: 150))
  imageContext.setFillColor(CGColor(gray: 1, alpha: 1))
  draw(title, x: CGFloat(100 + index * 290), y: 230, context: imageContext, size: 28)
  imageContext.setFillColor(CGColor(red: 0.04, green: 0.4, blue: 0.32, alpha: 1))
}
draw("GALPIUM · SAMPLE", x: 70, y: 430, context: imageContext, size: 40)
draw("자료 · 문서 · 원문 인용", x: 70, y: 80, context: imageContext, size: 25)
let image = imageContext.makeImage()!
let destination = CGImageDestinationCreateWithURL(
  directory.appendingPathComponent("샘플-자료연결.png") as CFURL, UTType.png.identifier as CFString, 1,
  nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("PNG export") }
try Data("샘플 비교표\n형식,검색,인용\n텍스트,본문 검색,문단 인용\nPDF,추출 본문 검색,쪽 인용\n이미지,이름 검색,본문 이미지\n".utf8).write(
  to: directory.appendingPathComponent("샘플-비교표.csv"))
