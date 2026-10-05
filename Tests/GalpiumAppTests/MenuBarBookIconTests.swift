import AppKit
import GalpiumCore
import SwiftUI
import XCTest

@testable import GalpiumApp

final class MenuBarBookIconTests: XCTestCase {
  func testLogoBookStatesRenderDistinctTemplateIconsAndSettingsLanguages() async throws {
    try await MainActor.run {
      var renders = [Data]()
      for connected in [false, true] {
        let image = MenuBarBookIcon.image(connected: connected)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(image.isTemplate)
        let bitmap = try XCTUnwrap(
          NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 72, pixelsHigh: 72, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 72, height: 72)).fill()
        image.draw(in: NSRect(x: 0, y: 0, width: 72, height: 72))
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let darkPixels = (0..<72).reduce(0) { count, y in
          count
            + (0..<72).filter { x in
              (bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)?.redComponent ?? 1) < 0.5
            }.count
        }
        XCTAssertGreaterThan(darkPixels, 100)
        renders.append(png)
        try png.write(
          to: URL(
            fileURLWithPath: "/private/tmp/galpium-book-" + (connected ? "open" : "closed") + ".png"
          ))
      }
      XCTAssertNotEqual(renders[0], renders[1])
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      let host = NSHostingView(
        rootView: SettingsView(
          model: model, appearance: .constant("system"), language: .constant("system")))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 580, height: 350), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      defer {
        window.contentView = nil
        window.close()
      }
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
        to: URL(fileURLWithPath: "/private/tmp/galpium-language-settings.png"))
    }
  }
}
