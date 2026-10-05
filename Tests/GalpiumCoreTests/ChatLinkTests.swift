import Foundation
import XCTest

@testable import GalpiumCore

final class ChatLinkTests: XCTestCase {
  private let link = "codex://threads/01900000-0000-7000-8000-000000000001"

  func testOnlyExistingChatNavigationIsAllowed() throws {
    XCTAssertEqual(try WikiValidation.provenanceURL(link), link)
    XCTAssertEqual(Markdown.safeLink(link), link)
    XCTAssertEqual(Markdown.inline("[대화](\(link))").first?.href, link)
    for unsafe in [
      "codex://threads/new", "codex://new?prompt=send", "codex://settings",
      "codex://plugins/install/example?marketplace=other", link + "?prompt=send",
      link + "#fragment", link + "/extra", link.replacingOccurrences(of: "threads", with: "other"),
      link.replacingOccurrences(of: "threads/", with: "user:secret@threads/"),
      link.replacingOccurrences(of: "threads/", with: "threads:1234/"),
      link.replacingOccurrences(of: "019", with: "%30%31%39"),
      "codex://threads/not-an-id", "javascript:alert(1)", "file:///etc/passwd",
    ] {
      XCTAssertNil(WikiValidation.chatDeepLink(unsafe), unsafe)
      XCTAssertNil(Markdown.safeLink(unsafe), unsafe)
      XCTAssertThrowsError(try WikiValidation.provenanceURL(unsafe), unsafe)
    }
    XCTAssertEqual(
      try WikiValidation.provenanceURL("https://chatgpt.com/c/example"),
      "https://chatgpt.com/c/example")
  }

  func testOriginalLinkRenderingPreservesUnicodeAndRejectsCommands() {
    let original =
      "요청: 引用を説明して。\n대화: `\(link)`。\n웹: https://chatgpt.com/c/example\n거부: \(link)?prompt=send"
    let rendered = Markdown.linkedOriginal(original)
    XCTAssertEqual(String(rendered.characters), original)
    let urls = rendered.runs.compactMap(\.link).map(\.absoluteString)
    XCTAssertTrue(urls.contains(link), urls.description)
    XCTAssertTrue(urls.contains("https://chatgpt.com/c/example"), urls.description)
    XCTAssertFalse(urls.contains { $0.contains("prompt=send") }, urls.description)
  }

  func testMCPChatProvenanceSurvivesCitationAndBackup() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let copyRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: copyRoot)
    }
    let store = try WikiStore(root: root)
    let server = MCPServer(store: store)
    let prompt = "요청 프롬프트: 자료와 도표로 설명해줘.\n채팅: \(link)"
    let result = try server.call("material_add", ["title": "작성 기록", "body": prompt, "url": link])
    let item = try XCTUnwrap(result["material"] as? [String: Any])
    let id = try XCTUnwrap(item["id"] as? String)
    let original = try store.material(id)
    let citation = try store.makeCitation(materialID: id, page: 1, quote: prompt, id: "context")
    _ = try store.updateMaterial(id, title: "생성 기록", expectedRevision: 1)
    try store.validateCitation(citation)
    XCTAssertEqual(try store.material(id).originalHash, original.originalHash)
    XCTAssertEqual(try store.materialExtraction(id)?.pages.first?.text, prompt)
    XCTAssertThrowsError(
      try server.call(
        "material_add", ["title": "Invalid", "body": prompt, "url": "codex://threads/new"]))
    XCTAssertEqual(try store.materials().count, 1)
    let backup = root.appendingPathComponent("backup")
    try store.backup(to: backup)
    let copy = try WikiStore(root: copyRoot)
    _ = try copy.importBackup(from: backup)
    XCTAssertEqual(try copy.material(id).url, link)
    XCTAssertEqual(try copy.material(id).originalHash, original.originalHash)
    try copy.validateCitation(citation)
  }
}
