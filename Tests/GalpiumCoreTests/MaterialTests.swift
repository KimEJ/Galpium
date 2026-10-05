import CoreGraphics
import CoreText
import Foundation
import XCTest

@testable import GalpiumCore

final class MaterialTests: XCTestCase {
  private func store() throws -> WikiStore {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    return try WikiStore(root: root)
  }
  func testUnifiedMaterialsCitationRenameHistoryAndBackup() throws {
    let db = try store()
    let material = try db.addTextMaterial(title: "회의록", body: "백업에는 첨부파일과 문서 이력이 포함됩니다.")
    let citation = try db.makeCitation(
      materialID: material.id, page: 1, quote: "백업에는 첨부파일과 문서 이력이 포함됩니다.", id: "ref-a")
    var page = try db.upsert(
      WikiPage(
        slug: "notes", title: "정리",
        body:
          "백업을 사용하세요.[^ref-a]\n\n[^ref-a]: [회의록](material:\(material.id))\n    > 백업에는 첨부파일과 문서 이력이 포함됩니다.",
        citations: [citation]), expectedRevision: 0)
    XCTAssertEqual(try db.materialReferences(material.id).count, 1)
    XCTAssertThrowsError(
      try db.makeCitation(materialID: material.id, page: 1, quote: "없는 문장", id: "ref-b"))
    let renamed = try db.updateMaterial(material.id, title: "회의록 변경", expectedRevision: 1)
    XCTAssertEqual(renamed.originalHash, material.originalHash)
    try db.validateCitation(citation)
    page.body = "현재 본문에서 인용 제거"
    page = try db.upsert(page, expectedRevision: 1)
    XCTAssertEqual(page.citations, [])
    XCTAssertTrue(try db.materialReferences(material.id).first!.historical)
    XCTAssertThrowsError(try db.deleteMaterial(material.id, expectedRevision: 2))
    let backup = db.root.appendingPathComponent("backup")
    try db.backup(to: backup)
    let copy = try store()
    _ = try copy.importBackup(from: backup)
    try copy.validateCitation(citation)
    XCTAssertEqual(try copy.material(material.id).title, "회의록 변경")
    XCTAssertEqual(try copy.page("notes", revision: 1).citations, [citation])
    XCTAssertEqual(
      try copy.extraction(citation.extractionID), try db.extraction(citation.extractionID))
    let unsourced = try copy.upsert(
      WikiPage(slug: "direct", title: "직접 작성", body: "메모"), expectedRevision: 0)
    XCTAssertEqual(unsourced.sources, [])
    XCTAssertEqual(try copy.materials().count, 1)
  }
  func testDistinctProvenanceSharesBytesButKeepsMaterialsAndFileExtension() throws {
    let db = try store()
    let data = Data("same original".utf8)
    let a = try db.importMaterial(data: data, name: "a.txt", url: "https://example.com/a")
    let b = try db.importMaterial(data: data, name: "a.txt", url: "https://example.com/b")
    XCTAssertNotEqual(a.id, b.id)
    XCTAssertEqual(a.fileID, b.fileID)
    XCTAssertEqual(try db.materials().count, 2)
    XCTAssertEqual(
      try db.importMaterial(data: data, name: "a.txt", url: "https://example.com/a").id, a.id)
    XCTAssertThrowsError(try db.updateMaterial(a.id, title: "a.pdf", expectedRevision: 1))
    let archived = try db.updateMaterial(a.id, status: "archived", expectedRevision: 1)
    XCTAssertEqual(try db.materials().map(\.id), [b.id])
    try db.deleteMaterial(archived.id, expectedRevision: 2)
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(db.materialFileURL(b))), data)
  }
  func testPDFExtractionPageCitationAndKeywordSearch() throws {
    let db = try store()
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 400, height: 500)
    let consumer = try XCTUnwrap(CGDataConsumer(data: data))
    let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
    for text in ["First page: local backups.", "Second page: citations preserve evidence."] {
      context.beginPDFPage(nil)
      context.textPosition = CGPoint(x: 20, y: 440)
      let line = CTLineCreateWithAttributedString(
        NSAttributedString(
          string: text,
          attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
              "Helvetica" as CFString, 14, nil)
          ]))
      CTLineDraw(line, context)
      context.endPDFPage()
    }
    context.closePDF()
    let material = try db.importMaterial(data: data as Data, name: "paper.pdf")
    let text = try XCTUnwrap(db.materialExtraction(material.id))
    XCTAssertEqual(text.pages.map(\.number), [1, 2])
    let quote = text.pages[1].text.trimmingCharacters(in: .whitespacesAndNewlines)
    let ref = try db.makeCitation(materialID: material.id, page: 2, quote: quote, id: "ref-pdf")
    XCTAssertEqual(ref.page, 2)
    XCTAssertEqual(try db.searchMaterials(query: "citations").items.map(\.id), [material.id])
    XCTAssertEqual(
      Markdown.footnotes("Body[^a]\n\n[^a]: test\n    continuation").first?.text,
      "test\ncontinuation")
    XCTAssertEqual(
      Markdown.inline("Text[^a] `[^ignored]`").filter { $0.kind == "footnote" }.map(\.text), ["a"])
  }
  func testV2MigrationPreservesRawHistoryAliasesAndRejectsOldWriters() throws {
    let old = try store()
    let source = try old.ingest(slug: "legacy", title: "Legacy", body: "original")
    let file = try old.attach(data: Data("legacy bytes".utf8), name: "legacy.txt")
    _ = try old.upsert(
      WikiPage(
        slug: "legacy-page", title: "Legacy page", body: "[file](attachment:\(file.id))",
        sources: [source.slug]), expectedRevision: 0)
    let raw = try old.db.query("SELECT data FROM revisions")[0][0]
    try old.db.executeScript(
      "DROP TRIGGER page_writer_insert; DROP TRIGGER page_writer_update; DROP TRIGGER extraction_immutable_update; DROP TRIGGER source_immutable_delete; DROP TABLE page_materials; DROP TABLE material_extracts; DROP TABLE materials; CREATE TRIGGER source_immutable_delete BEFORE DELETE ON sources BEGIN SELECT RAISE(ABORT,'immutable source'); END; PRAGMA user_version=2;"
    )
    let migrated = try WikiStore(root: old.root)
    XCTAssertEqual(try migrated.db.query("PRAGMA user_version")[0][0], "3")
    XCTAssertEqual(try migrated.db.query("SELECT data FROM revisions")[0][0], raw)
    XCTAssertEqual(try migrated.materials().count, 2)
    XCTAssertEqual(try migrated.materialReferences(WikiMaterial.fileID(file.id)).count, 1)
    var legacy = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String: Any]
    legacy.removeValue(forKey: "materials")
    legacy.removeValue(forKey: "citations")
    let json = String(decoding: try JSONSerialization.data(withJSONObject: legacy), as: UTF8.self)
    XCTAssertThrowsError(
      try old.db.execute("UPDATE pages SET data=? WHERE slug='legacy-page'", [json]))
    let snapshots = try FileManager.default.contentsOfDirectory(atPath: old.root.path).filter {
      $0.hasPrefix("migration-v2-") && $0.hasSuffix(".sqlite3")
    }
    XCTAssertEqual(snapshots.count, 1)
  }
  func testCanonicalDeletionRollbackRestoresMetadataAndBytes() throws {
    let db = try store()
    let item = try db.importMaterial(data: Data("recoverable".utf8), name: "rollback.txt")
    let url = try XCTUnwrap(db.materialFileURL(item))
    try db.db.executeScript(
      "CREATE TRIGGER fail_file_delete BEFORE DELETE ON attachments BEGIN SELECT RAISE(ABORT,'simulated failure'); END;"
    )
    XCTAssertThrowsError(try db.deleteMaterial(item.id, expectedRevision: 1))
    XCTAssertEqual(try db.material(item.id), item)
    XCTAssertEqual(try Data(contentsOf: url), Data("recoverable".utf8))
  }
  func testMCPMaterialsAndValidatedFootnotes() throws {
    let server = MCPServer(store: try store())
    let added = try server.call(
      "material_add", ["title": "Note", "body": "Evidence remains local."])
    let material = try XCTUnwrap(added["material"] as? [String: Any])
    let id = try XCTUnwrap(material["id"] as? String)
    XCTAssertEqual(
      try server.call("material_read", ["id": id, "limit": 8])["text"] as? String, "Evidence")
    XCTAssertEqual(
      try server.call("material_search", ["query": "Evidence", "kind": "text"])["total"] as? Int, 1)
    let schema =
      MCPServer.tools.first { $0["name"] as? String == "galpium_wiki_material_search" }![
        "inputSchema"] as! [String: Any]
    let properties = schema["properties"] as! [String: [String: Any]]
    XCTAssertTrue((properties["kind"]!["enum"] as! [String]).contains("pdf"))
    let cited = try server.call(
      "citation",
      ["material_id": id, "page": 1, "quote": "Evidence remains local.", "id": "ref-note"])
    let footnote = try XCTUnwrap(cited["footnote"] as? String)
    let citation = try XCTUnwrap(cited["citation"] as? [String: Any])
    _ = try server.call(
      "upsert",
      [
        "slug": "compiled", "title": "Compiled", "body": "Local.[^ref-note]\n\n" + footnote,
        "citations": [citation], "expected_revision": 0,
      ])
    XCTAssertEqual(try server.store.page("compiled").citations.count, 1)
    XCTAssertFalse(try server.store.lint().contains { $0["code"] == "uncompiled_source" })
    XCTAssertThrowsError(
      try server.call(
        "citation", ["material_id": id, "page": 1, "quote": "fabricated", "id": "ref-false"]))
    XCTAssertEqual(try server.call("material_search", ["query": "Evidence"])["total"] as? Int, 1)
  }
}
