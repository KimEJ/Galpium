import Foundation
import XCTest

@testable import GalpiumCore

final class SemanticTests: XCTestCase {
  func testCorruptCacheDatabasePreservesDocumentsAndRebuilds() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WikiStore(root: root)
    _ = try store.ingest(slug: "source", title: "Original", body: "unchanged")
    let dir = root.appendingPathComponent("search-cache")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("broken sqlite file".utf8).write(to: dir.appendingPathComponent("embedding.sqlite3"))
    _ = try SemanticCache(root: root)
    XCTAssertEqual(try store.source("source").body, "unchanged")
    XCTAssertTrue(
      try FileManager.default.contentsOfDirectory(atPath: dir.path).contains {
        $0.hasPrefix("corrupt-")
      })
  }
  func testLibraryAliasesShareOneSocketAddress() throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: parent) }
    let actual = parent.appendingPathComponent("actual")
    try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: true)
    let alias = parent.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: actual)
    XCTAssertEqual(
      try EmbeddingSocket(root: actual).socketPath, try EmbeddingSocket(root: alias).socketPath)
  }
  func testDerivedVectorsNeverMatchChangedArchivedOrWrongTagPages() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WikiStore(root: root)
    let source = try store.ingest(slug: "source", title: "Original", body: "original bytes")
    var page = try store.upsert(
      WikiPage(
        slug: "page", title: "Backup", body: "Full backup keeps history and attachments",
        sources: [source.slug], tags: ["operations"]), expectedRevision: 0)
    let cache = try SemanticCache(root: root)
    var vector = [Float](repeating: 0, count: 768)
    vector[0] = 1
    let passage = SemanticPassage(
      id: "test-vector", slug: page.slug, digest: SemanticCache.digest(page), heading: "Backup",
      excerpt: page.body, input: page.body)
    try cache.saveVector(passage.id, vector)
    try cache.replace(page, passages: [passage])
    XCTAssertEqual(try cache.missing(store.pages()).count, 0)
    XCTAssertEqual(try cache.matches(query: vector, pages: store.pages())[page.slug]?.revision, 1)
    XCTAssertTrue(try cache.matches(query: vector, pages: store.pages(tag: "other")).isEmpty)
    page.body = "Changed contents"
    page = try store.upsert(page, expectedRevision: 1)
    XCTAssertEqual(try cache.missing(store.pages()).count, 1)
    XCTAssertTrue(try cache.matches(query: vector, pages: store.pages()).isEmpty)
    _ = try store.archive(page.slug, expectedRevision: page.revision)
    XCTAssertTrue(try cache.matches(query: vector, pages: store.pages()).isEmpty)
    XCTAssertEqual(try store.source(source.slug).body, "original bytes")
    XCTAssertEqual(try store.history(page.slug).count, 3)
  }
  func testCorruptVectorsAreRebuiltAndInvalidValuesRejected() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WikiStore(root: root)
    let source = try store.ingest(slug: "source", title: "Original", body: "data")
    let page = try store.upsert(
      WikiPage(slug: "page", title: "Page", body: "body", sources: [source.slug]),
      expectedRevision: 0)
    let cache = try SemanticCache(root: root)
    let p = SemanticPassage(
      id: "broken", slug: page.slug, digest: SemanticCache.digest(page), heading: "",
      excerpt: page.body, input: page.body)
    try cache.db.execute("INSERT INTO vectors VALUES (?,?)", [p.id, "not-base64"])
    try cache.replace(page, passages: [p])
    XCTAssertEqual(try cache.missing([page]).count, 1)
    XCTAssertNil(try cache.vector(p.id))
    XCTAssertThrowsError(try cache.saveVector("bad", [Float.infinity]))
    XCTAssertThrowsError(try cache.saveVector("zero", Array(repeating: 0, count: 768)))
    var vector = Array(repeating: Float(0), count: 768)
    vector[7] = 4
    try cache.saveVector(p.id, vector)
    XCTAssertEqual(try XCTUnwrap(cache.vector(p.id))[7], 1)
    XCTAssertTrue(try cache.missing([page]).isEmpty)
    try cache.prune([])
    XCTAssertNil(try cache.vector(p.id))
  }
  func testFallbackKeepsKeywordFilteringAndPagination() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WikiStore(root: root)
    let source = try store.ingest(slug: "source", title: "Original", body: "data")
    for i in 0..<3 {
      _ = try store.upsert(
        WikiPage(
          slug: "page-\(i)", title: "Backup \(i)", body: "backup file", sources: [source.slug],
          tags: ["tag"]), expectedRevision: 0)
    }
    let result = try store.hybridSearch(query: "backup", tag: "tag", limit: 1, offset: 1)
    XCTAssertEqual(result.total, 3)
    XCTAssertEqual(result.items.count, 1)
    XCTAssertTrue(try store.hybridSearch(query: "backup", tag: "missing").items.isEmpty)
    XCTAssertThrowsError(try store.hybridSearch(query: "backup", offset: -1))
    XCTAssertThrowsError(try store.hybridSearch(query: ""))
    let archived = try store.hybridSearch(query: "backup", status: "archived")
    XCTAssertEqual(archived.status.state, "not_applicable")
  }
}
