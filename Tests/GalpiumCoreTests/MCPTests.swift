import Foundation
import XCTest

@testable import GalpiumCore

final class MCPTests: XCTestCase {
  private var root: URL!
  private var server: MCPServer!
  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    server = MCPServer(store: try WikiStore(root: root))
  }
  override func tearDownWithError() throws {
    server = nil
    try FileManager.default.removeItem(at: root)
  }
  private func rpc(_ method: String, _ params: [String: Any] = [:], id: Any = 1) throws -> [String:
    Any]
  {
    try XCTUnwrap(
      server.handle(
        JSONSerialization.data(withJSONObject: [
          "jsonrpc": "2.0", "id": id, "method": method, "params": params,
        ])))
  }
  private func initialize() throws {
    _ = try rpc(
      "initialize",
      [
        "protocolVersion": "2025-11-25", "capabilities": [:],
        "clientInfo": ["name": "test", "version": "1"],
      ])
  }
  func testProtocolNegotiatesAndNotificationsNeverRespond() throws {
    XCTAssertNotNil(try rpc("tools/list")["error"])
    let initialized =
      try rpc(
        "initialize",
        [
          "protocolVersion": "2099-01-01", "capabilities": [:],
          "clientInfo": ["name": "test", "version": "1"],
        ])["result"] as! [String: Any]
    XCTAssertEqual(initialized["protocolVersion"] as? String, "2025-11-25")
    XCTAssertNil(
      server.handle(Data("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}".utf8)))
    let tools = (try rpc("tools/list")["result"] as! [String: Any])["tools"] as! [[String: Any]]
    XCTAssertEqual(tools.count, 21)
    XCTAssertTrue(
      tools.allSatisfy {
        ($0["inputSchema"] as? [String: Any])?["additionalProperties"] as? Bool == false
      })
    XCTAssertNotNil(try rpc("unknown")["error"])
  }
  func testJSONRPCParseRequestAndIDValidation() throws {
    XCTAssertEqual(
      (server.handle(Data("bad json".utf8))?["error"] as? [String: Any])?["code"] as? Int, -32700)
    XCTAssertEqual(
      (server.handle(Data("[]".utf8))?["error"] as? [String: Any])?["code"] as? Int, -32600)
    XCTAssertEqual((try rpc("ping", id: true)["error"] as? [String: Any])?["code"] as? Int, -32600)
    XCTAssertNotNil(try rpc("initialize")["error"])
  }
  func testToolsRejectUnknownFieldsAndInvalidNumericTypes() throws {
    let offsets: [Any] = [true, "1", -1, 1.5, NSNull()]
    let limits: [Any] = [0, 101, true, "20"]
    for invalid in offsets { XCTAssertThrowsError(try server.call("list", ["offset": invalid])) }
    for invalid in limits { XCTAssertThrowsError(try server.call("list", ["limit": invalid])) }
    XCTAssertThrowsError(try server.call("list", ["owner": "other"]))
    XCTAssertThrowsError(try server.call("list", ["kind": "source", "status": "all"]))
    XCTAssertThrowsError(try server.call("search", ["query": " "]))
    XCTAssertThrowsError(try server.call("attachment_refs", ["file_id": "../../etc/passwd"]))
  }
  func testToolCycleReportsConflictAndInsufficientEvidence() throws {
    try initialize()
    _ = try server.call("ingest", ["slug": "원본", "title": "자료", "body": "실제 근거"])
    let args: [String: Any] = [
      "slug": "문서", "title": "제목", "body": "실제 근거 [자료](source:원본)", "sources": ["원본"],
      "expected_revision": 0,
    ]
    let first =
      try rpc("tools/call", ["name": "galpium_wiki_upsert", "arguments": args])["result"]
      as! [String: Any]
    XCTAssertEqual(first["isError"] as? Bool, false)
    var edit = args
    edit["expected_revision"] = 1
    edit["body"] = "최신 내용"
    _ = try server.call("upsert", edit)
    var stale = args
    stale["expected_revision"] = 1
    stale["body"] = "뒤늦은 내용"
    let error =
      try rpc("tools/call", ["name": "galpium_wiki_upsert", "arguments": stale])["result"]
      as! [String: Any]
    XCTAssertEqual(error["isError"] as? Bool, true)
    XCTAssertEqual((error["structuredContent"] as? [String: Any])?["current_revision"] as? Int, 2)
    let retrieval = try server.call("search", ["query": "찾을수없는말"])["retrieval"] as! [String: Any]
    XCTAssertEqual(retrieval["evidence_status"] as? String, "insufficient")
    XCTAssertEqual(try server.call("history", ["slug": "문서"])["total"] as? Int, 2)
    XCTAssertEqual(try server.call("list", ["offset": 9_007_199_254_740_991])["total"] as? Int, 1)
  }
}
