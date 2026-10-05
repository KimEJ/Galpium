import CSQLite
import Foundation
import XCTest

@testable import GalpiumCore

final class MigrationTests: XCTestCase {
  private func legacy(root: URL, missingSource: Bool = false) throws -> String {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    var db: OpaquePointer?
    guard sqlite3_open(root.appendingPathComponent("wiki.sqlite3").path, &db) == SQLITE_OK else {
      throw WikiError.storage("fixture")
    }
    defer { sqlite3_close(db) }
    func sql(_ value: String) throws {
      guard sqlite3_exec(db, value, nil, nil, nil) == SQLITE_OK else {
        throw WikiError.storage(String(cString: sqlite3_errmsg(db)))
      }
    }
    try sql(
      "CREATE TABLE sources(slug TEXT PRIMARY KEY,data TEXT NOT NULL); CREATE TABLE pages(slug TEXT PRIMARY KEY,data TEXT NOT NULL); CREATE TABLE revisions(slug TEXT,revision INTEGER,data TEXT,PRIMARY KEY(slug,revision)); CREATE TABLE attachments(id TEXT PRIMARY KEY,data TEXT); CREATE TABLE log(id INTEGER PRIMARY KEY,data TEXT); CREATE TABLE drafts(slug TEXT PRIMARY KEY,data TEXT); PRAGMA user_version=1;"
    )
    let source = WikiSource(
      slug: "원본", title: "원본 메모", body: "수정하지 않은 원본", url: "", createdAt: WikiJSON.now(),
      sha256: nil)
    var page = WikiPage(
      slug: "문서", title: "한글 문서", body: "## 본문\n[[다른문서]]", sources: [missingSource ? "없음" : "원본"],
      tags: ["운영"], pinned: true, revision: 1, createdAt: WikiJSON.now(), updatedAt: WikiJSON.now())
    let original = try WikiJSON.encode(page)
    func quote(_ value: String) -> String {
      "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }
    try sql(
      "INSERT INTO sources VALUES('원본',\(quote(try WikiJSON.encode(source)))); INSERT INTO revisions VALUES('문서',1,\(quote(original)));"
    )
    page.revision = 2
    page.body += "\n마지막 개정"
    let current = try WikiJSON.encode(page)
    try sql(
      "INSERT INTO revisions VALUES('문서',2,\(quote(current))); INSERT INTO pages VALUES('문서',\(quote(current)));"
    )
    return original
  }
  func testV1MigrationPreservesImmutableHistoryAndCreatesRelationships() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = try legacy(root: root)
    let store = try WikiStore(root: root)
    XCTAssertEqual(try store.db.query("PRAGMA user_version")[0][0], "3")
    XCTAssertEqual(
      try store.db.query("SELECT data FROM revisions WHERE slug='문서' AND revision=1")[0][0],
      original)
    XCTAssertEqual(try store.source("원본").body, "수정하지 않은 원본")
    XCTAssertEqual(try store.db.query("SELECT source_slug FROM page_sources")[0][0], "원본")
    XCTAssertEqual(try store.db.query("SELECT tag FROM page_tags")[0][0], "운영")
    XCTAssertEqual(try store.pages(query: "마지막 개정").count, 1)
    XCTAssertTrue(try store.db.query("PRAGMA foreign_key_check").isEmpty)
    let backups = try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
      $0.hasPrefix("migration-v1-") && $0.hasSuffix(".sqlite3")
    }
    XCTAssertEqual(backups.count, 1)
    let backup = try SQLite(
      url: root.appendingPathComponent(try XCTUnwrap(backups.first)), readOnly: true)
    XCTAssertEqual(try backup.query("PRAGMA user_version")[0][0], "1")
    XCTAssertEqual(try backup.query("SELECT data FROM revisions WHERE revision=1")[0][0], original)
  }
  func testFailedMigrationRollsBackWithoutChangingVersionOrHistory() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = try legacy(root: root, missingSource: true)
    XCTAssertThrowsError(try WikiStore(root: root))
    let readOnly = try SQLite(url: root.appendingPathComponent("wiki.sqlite3"), readOnly: true)
    XCTAssertEqual(try readOnly.query("PRAGMA user_version")[0][0], "1")
    XCTAssertEqual(
      try readOnly.query("SELECT data FROM revisions WHERE revision=1")[0][0], original)
    XCTAssertTrue(
      try readOnly.query("SELECT name FROM sqlite_master WHERE name='page_sources'").isEmpty)
  }
  func testDatabaseConstraintsAndDiskFullKeepCommittedDocument() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WikiStore(root: root)
    _ = try store.ingest(slug: "원본", title: "자료", body: "근거")
    let page = try store.upsert(
      WikiPage(slug: "문서", title: "제목", body: "본문", sources: ["원본"]), expectedRevision: 0)
    XCTAssertThrowsError(try store.db.execute("INSERT INTO page_sources VALUES('문서','없는원본')"))
    XCTAssertThrowsError(try store.db.execute("UPDATE revisions SET data='{}'"))
    XCTAssertThrowsError(try store.db.execute("UPDATE sources SET body='변경'"))
    XCTAssertThrowsError(try store.db.execute("UPDATE pages SET status='unknown'"))
    let count = Int(try store.db.query("PRAGMA page_count")[0][0])!
    try store.db.execute("PRAGMA max_page_count=\(count)")
    XCTAssertThrowsError(
      try store.ingest(slug: "큰원본", title: "큰 자료", body: String(repeating: "큰", count: 85000)))
    XCTAssertEqual(try store.page("문서"), page)
    XCTAssertEqual(try store.sources().count, 1)
    XCTAssertTrue(try store.db.query("PRAGMA foreign_key_check").isEmpty)
  }
  func testSQLPaginationCountsAndSubstringFallback() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WikiStore(root: root)
    _ = try store.ingest(slug: "원본", title: "자료", body: "근거")
    for i in 0..<25 {
      _ = try store.upsert(
        WikiPage(
          slug: "page-\(i)", title: "문서 \(i)", body: "C++ 배포 확인 문서식별자\(i)", sources: ["원본"],
          tags: [i % 2 == 0 ? "운영" : "개발"]), expectedRevision: 0)
    }
    XCTAssertEqual(try store.pageCount(query: "C++ 배포"), 25)
    XCTAssertEqual(try store.pageSummaries(limit: 10, offset: 20).count, 5)
    XCTAssertEqual(try store.pageCount(tag: "운영"), 13)
    XCTAssertEqual(try store.pageSummaries(query: "문서식별자24").first?.slug, "page-24")
    XCTAssertEqual(
      try store.pageSummaries(query: "문서식별자24".decomposedStringWithCanonicalMapping).count, 1)
  }
}
