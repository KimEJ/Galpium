import AppKit
import Foundation
import GalpiumCore
import SwiftUI
import XCTest

@testable import GalpiumApp

final class ConnectionStatusTests: XCTestCase {
  func testMenuBarUpdatesConnectionAndRetainsWindowActions() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      let delegate = AppDelegate()
      delegate.model = model
      let status = try XCTUnwrap(delegate.connectionMenuBar)
      defer { status.remove() }
      XCTAssertTrue(status.statusItem.button?.image?.isTemplate == true)
      XCTAssertTrue(status.statusItem.button?.toolTip?.contains(model.connections.label) == true)
      let server = MCPServer(store: try XCTUnwrap(model.store), reportConnections: true)
      _ = server.handle(
        try JSONSerialization.data(withJSONObject: [
          "jsonrpc": "2.0", "id": 1, "method": "initialize",
          "params": [
            "protocolVersion": "2025-11-25", "capabilities": [:],
            "clientInfo": ["name": "Codex", "version": "1"],
          ],
        ]))
      model.connections.refresh(root: root)
      status.update()
      let menu = try XCTUnwrap(status.statusItem.menu)
      XCTAssertEqual(menu.items.first?.title, model.connections.label)
      XCTAssertTrue(menu.items.contains { $0.title == "Codex" })
      XCTAssertFalse(menu.autoenablesItems)
      XCTAssertTrue(menu.items.contains { $0.title == localized("Galpium 열기") && $0.action != nil })
      XCTAssertTrue(menu.items.contains { $0.title == localized("AI 연결 설정") && $0.action != nil })
    }
  }
  func testStatusUsesLiveSessionsAndRendersInReadingAndEditing() async throws {
    try await MainActor.run {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      let server = MCPServer(store: try XCTUnwrap(model.store), reportConnections: true)
      XCTAssertFalse(model.connections.isConnected)
      _ = server.handle(
        try JSONSerialization.data(withJSONObject: [
          "jsonrpc": "2.0", "id": 1, "method": "initialize",
          "params": [
            "protocolVersion": "2025-11-25", "capabilities": [:],
            "clientInfo": ["name": "Codex", "version": "1"],
          ],
        ]))
      model.connections.refresh(root: root)
      XCTAssertTrue(model.connections.isConnected)
      XCTAssertEqual(model.connections.clients.first?.name, "Codex")
      let host = NSHostingView(rootView: ContentView(model: model, delegate: AppDelegate()))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      defer {
        window.contentView = nil
        window.close()
      }
      for name in ["reading", "editing"] {
        if name == "editing" { model.newPage() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/private/tmp/galpium-connection-" + name + ".png"))
      }
      model.connections.refresh(root: root.appendingPathComponent("other"))
      XCTAssertFalse(model.connections.isConnected)
    }
  }
}
