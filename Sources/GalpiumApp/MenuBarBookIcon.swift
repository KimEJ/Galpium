import AppKit

@MainActor
enum MenuBarBookIcon {
  static func image(connected: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
      NSColor.black.setFill()
      if connected {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: 1, yBy: 2)
        transform.scale(by: 16 / 544)
        transform.translateX(by: -240, yBy: -276)
        transform.concat()
        // Preserve the app logo's two curved pages and bookmark in a menu-bar silhouette.
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
        NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
        let ribbon = NSBezierPath()
        ribbon.move(to: NSPoint(x: 666, y: 730))
        ribbon.line(to: NSPoint(x: 716, y: 740))
        ribbon.line(to: NSPoint(x: 716, y: 566))
        ribbon.line(to: NSPoint(x: 691, y: 591))
        ribbon.line(to: NSPoint(x: 666, y: 566))
        ribbon.close()
        ribbon.fill()
        NSGraphicsContext.restoreGraphicsState()
      } else {
        NSBezierPath(
          roundedRect: NSRect(x: 3, y: 2, width: 12, height: 14), xRadius: 1.5, yRadius: 1.5
        ).fill()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
        NSBezierPath(
          roundedRect: NSRect(x: 4.4, y: 3, width: 9.2, height: 1), xRadius: 0.5, yRadius: 0.5
        ).fill()
        let spine = NSBezierPath()
        spine.move(to: NSPoint(x: 5, y: 5))
        spine.line(to: NSPoint(x: 5, y: 15))
        spine.lineWidth = 0.75
        spine.stroke()
        let ribbon = NSBezierPath()
        ribbon.move(to: NSPoint(x: 10.2, y: 16))
        ribbon.line(to: NSPoint(x: 12.2, y: 16))
        ribbon.line(to: NSPoint(x: 12.2, y: 10.5))
        ribbon.line(to: NSPoint(x: 11.2, y: 11.5))
        ribbon.line(to: NSPoint(x: 10.2, y: 10.5))
        ribbon.close()
        ribbon.fill()
        NSGraphicsContext.restoreGraphicsState()
      }
      return true
    }
    image.isTemplate = true
    return image
  }
}
