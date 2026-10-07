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
    try Data("broken sqlite file".utf8).write(
      to: dir.appendingPathComponent(EmbeddingAssets.cacheFilename))
    _ = try SemanticCache(root: root)
    XCTAssertEqual(try store.source("source").body, "unchanged")
    XCTAssertTrue(
      try FileManager.default.contentsOfDirectory(atPath: dir.path).contains {
        $0.hasPrefix("corrupt-")
      })
  }
  func testModelNamespaceDoesNotReuseOrRemoveLegacyCache() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let dir = root.appendingPathComponent("search-cache")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let legacy = dir.appendingPathComponent("embedding.sqlite3")
    let original = Data("legacy model vectors must stay isolated".utf8)
    try original.write(to: legacy)
    let cache = try SemanticCache(root: root)
    XCTAssertEqual(try Data(contentsOf: legacy), original)
    XCTAssertTrue(try cache.db.query("SELECT id FROM vectors").isEmpty)
    XCTAssertNotEqual(EmbeddingAssets.cacheFilename, legacy.lastPathComponent)
    XCTAssertTrue(EmbeddingAssets.identity.contains("jpeg2048:audio20mono16k"))
  }
  func testMediaRanksPreserveLocationsInSharedVectorSpace() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = try SemanticCache(root: root)
    var query = [Float](repeating: 0, count: 768)
    query[0] = 1
    var revisions = [String: Int]()
    for (slug, kind, cosine) in [
      ("material:z-text", "text", Float(0.95)),
      ("material:a-image", "image", Float(0.3)),
      ("material:b-audio", "audio", Float(0.2)),
    ] {
      let page = WikiPage(slug: slug, title: "Original", body: "", revision: 1)
      let media =
        kind == "text"
        ? nil
        : SemanticMediaItem(
          materialID: String(slug.dropFirst(9)), originalHash: "immutable-hash", kind: kind,
          pageNumber: kind == "image" ? 7 : nil,
          startSeconds: kind == "audio" ? 20 : nil, endSeconds: kind == "audio" ? 40 : nil)
      let passage = SemanticPassage(
        id: slug, slug: slug, digest: SemanticCache.digest(page), heading: "",
        excerpt: kind == "text" ? "actual original text" : "", input: "", media: media)
      var vector = query
      vector[0] = cosine
      vector[1] = sqrt(1 - cosine * cosine)
      try cache.saveVector(passage.id, vector)
      try cache.replace(page, passages: [passage])
      revisions[slug] = 1
    }
    let ranked = try cache.rankedMatches(query: query, revisions: revisions)
    // An unrelated singleton audio/image candidate must not displace a more similar text.
    XCTAssertEqual(ranked.map(\.key), ["material:z-text", "material:a-image", "material:b-audio"])
    let image = try XCTUnwrap(ranked.first { $0.key == "material:a-image" }?.match)
    XCTAssertEqual(image.page, 7)
    XCTAssertEqual(image.method, "visual")
    XCTAssertEqual(image.modality, "image")
    XCTAssertEqual(image.excerpt, "")
    let audio = try XCTUnwrap(ranked.first { $0.key == "material:b-audio" }?.match)
    XCTAssertEqual(audio.startSeconds, 20)
    XCTAssertEqual(audio.endSeconds, 40)
    XCTAssertEqual(audio.method, "audio")
    XCTAssertNil(audio.page)
    revisions["material:a-image"] = 2
    revisions.removeValue(forKey: "material:b-audio")
    XCTAssertEqual(
      try cache.rankedMatches(query: query, revisions: revisions).map(\.key), ["material:z-text"])
  }
  func testFailuresRespectRevisionCooldownAndDeletion() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WikiStore(root: root)
    let material = try store.addTextMaterial(title: "Original", body: "Preserve these bytes")
    let page = try store.semanticDocument("material:" + material.id)
    let cache = try SemanticCache(root: root)
    var vector = [Float](repeating: 0, count: 768)
    vector[0] = 1
    let passage = SemanticPassage(
      id: "original", slug: page.slug, digest: SemanticCache.digest(page), heading: "",
      excerpt: page.body, input: page.body)
    try cache.saveVector(passage.id, vector)
    try cache.replace(page, passages: [passage])
    XCTAssertEqual(try cache.matches(query: vector, pages: [page]).count, 1)
    try cache.recordFailure(page)
    XCTAssertTrue(try cache.matches(query: vector, pages: [page]).isEmpty)
    XCTAssertEqual(try cache.coverage([page.slug: page.revision]), 0)
    XCTAssertTrue(try cache.recentlyFailed(page.slug, revision: page.revision))
    XCTAssertFalse(try cache.recentlyFailed(page.slug, revision: page.revision + 1))
    XCTAssertEqual(try cache.failureCount([page.slug: page.revision]), 1)
    XCTAssertEqual(try cache.failureCount([page.slug: page.revision + 1]), 0)
    try cache.db.execute("UPDATE failures SET failed_at=0")
    XCTAssertFalse(try cache.recentlyFailed(page.slug, revision: page.revision))
    try store.deleteMaterial(material.id, expectedRevision: material.revision)
    XCTAssertNil(try store.semanticRevisions()[page.slug])
    try cache.prune(Set(try store.semanticRevisions().keys))
    XCTAssertTrue(try cache.db.query("SELECT slug FROM failures").isEmpty)
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
