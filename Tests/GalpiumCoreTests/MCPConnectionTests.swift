import Darwin
import Foundation
import XCTest

@testable import GalpiumCore

final class MCPConnectionTests: XCTestCase {
  private func root() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }
  func testInitializedClientsIdleBusyExpiryCloseAndLibraryIsolation() throws {
    let root = root()
    let a = MCPConnectionReporter(root: root)
    let b = MCPConnectionReporter(root: root)
    defer {
      a.close()
      b.close()
    }
    XCTAssertTrue(try MCPConnections.clients(for: root).isEmpty)
    a.initialize(name: "Codex", version: "1")
    b.initialize(name: "Another client", version: "1")
    XCTAssertEqual(try MCPConnections.clients(for: root).map(\.name), ["Another client", "Codex"])
    XCTAssertTrue(try MCPConnections.clients(for: self.root()).isEmpty)
    a.setBusy(true)
    XCTAssertTrue(
      try XCTUnwrap(MCPConnections.clients(for: root).first { $0.name == "Codex" }).isBusy)
    a.setBusy(false)
    XCTAssertFalse(
      try XCTUnwrap(MCPConnections.clients(for: root).first { $0.name == "Codex" }).isBusy)
    XCTAssertTrue(
      try MCPConnections.clients(for: root, now: Date().timeIntervalSince1970 + 9).isEmpty)
    a.close()
    XCTAssertEqual(try MCPConnections.clients(for: root).map(\.name), ["Another client"])
    b.close()
    XCTAssertTrue(try MCPConnections.clients(for: root).isEmpty)
    let directory = MCPConnections.directory(for: root)
    let dead = MCPClientConnection(
      id: "dead", name: "Dead", version: "1", pid: Int32.max, isBusy: false,
      updatedAt: Date().timeIntervalSince1970)
    let file = directory.appendingPathComponent("dead.json")
    defer { try? FileManager.default.removeItem(at: file) }
    try JSONEncoder().encode(dead).write(to: file)
    XCTAssertTrue(try MCPConnections.clients(for: root).isEmpty)
  }
  func testSelfProbeAndInvalidInitializeAreNotConnections() throws {
    let root = root()
    defer { try? FileManager.default.removeItem(at: root) }
    var server: MCPServer? = MCPServer(store: try WikiStore(root: root), reportConnections: true)
    let invalid = Data(
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}".utf8)
    XCTAssertNotNil(server?.handle(invalid)?["error"])
    XCTAssertTrue(try MCPConnections.clients(for: root).isEmpty)
    func message(_ name: String) throws -> Data {
      try JSONSerialization.data(withJSONObject: [
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": [
          "protocolVersion": "2025-11-25", "capabilities": [:],
          "clientInfo": ["name": name, "version": "1"],
        ],
      ])
    }
    _ = server?.handle(try message("Galpium connection check"))
    XCTAssertTrue(try MCPConnections.clients(for: root).isEmpty)
    _ = server?.handle(try message("Codex\nClient"))
    XCTAssertEqual(try MCPConnections.clients(for: root).first?.name, "CodexClient")
    server = nil
    XCTAssertTrue(try MCPConnections.clients(for: root).isEmpty)
  }
}
