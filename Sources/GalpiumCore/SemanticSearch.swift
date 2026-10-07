import Accelerate
import Foundation

public struct SemanticStatus: Codable, Sendable {
  public var state: String
  public var indexedPages: Int
  public var totalPages: Int
  public var indexedMaterials: Int = 0
  public var totalMaterials: Int = 0
  public var failedMaterials: Int = 0
  public var failedPages: Int = 0
  public var pending: Bool { indexedPages < totalPages || indexedMaterials < totalMaterials }
}
public struct HybridResult: Sendable {
  public var items: [PageSummary]
  public var total: Int
  public var status: SemanticStatus
  public var matches: [String: SemanticMatch]
}
public struct SemanticMatch: Codable, Sendable {
  public var excerpt: String
  public var heading: String
  public var similarity: Float
  public var method: String
  public var revision: Int
  public var page: Int? = nil
  public var modality: String? = nil
  public var startSeconds: Double? = nil
  public var endSeconds: Double? = nil
}

struct SemanticPassage: Codable, Sendable {
  var id: String
  var slug: String
  var digest: String
  var heading: String
  var excerpt: String
  var input: String
  var media: SemanticMediaItem? = nil
  var pageNumber: Int? = nil
}

/// Search cache is derived data. A failed/corrupt vector is ignored, never treated as a page.
final class SemanticCache: @unchecked Sendable {
  let db: SQLite
  init(root: URL) throws {
    let dir = root.appendingPathComponent("search-cache")
    try FileManager.default.createDirectory(
      at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let file = dir.appendingPathComponent(EmbeddingAssets.cacheFilename)
    do { db = try SQLite(url: file, derived: true) } catch {
      let message = error.localizedDescription
      guard
        message.contains("not a database") || message.contains("malformed")
          || message.contains("invalid search cache")
      else { throw error }
      let preserved = dir.appendingPathComponent("corrupt-" + UUID().uuidString + ".sqlite3")
      try FileManager.default.moveItem(at: file, to: preserved)
      for ext in ["-wal", "-shm"] {
        try? FileManager.default.moveItem(atPath: file.path + ext, toPath: preserved.path + ext)
      }
      db = try SQLite(url: file, derived: true)
    }
    try db.executeScript(
      """
      CREATE TABLE IF NOT EXISTS vectors (id TEXT PRIMARY KEY, vector TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS passages (id TEXT NOT NULL, slug TEXT NOT NULL, digest TEXT NOT NULL, data TEXT NOT NULL, PRIMARY KEY(slug,id));
      CREATE TABLE IF NOT EXISTS indexed (slug TEXT PRIMARY KEY, digest TEXT NOT NULL, revision INTEGER NOT NULL DEFAULT 0);
      CREATE INDEX IF NOT EXISTS passage_slug ON passages(slug);
      CREATE TABLE IF NOT EXISTS failures (slug TEXT PRIMARY KEY, revision INTEGER NOT NULL, failed_at REAL NOT NULL);
      """)
    try db.transaction {
      if !((try db.query("PRAGMA table_info(indexed)")).contains { $0[1] == "revision" }) {
        try db.execute("ALTER TABLE indexed ADD COLUMN revision INTEGER NOT NULL DEFAULT 0")
      }
    }
    for name in [
      EmbeddingAssets.cacheFilename, EmbeddingAssets.cacheFilename + "-wal",
      EmbeddingAssets.cacheFilename + "-shm",
    ] {
      let file = dir.appendingPathComponent(name)
      if FileManager.default.fileExists(atPath: file.path) {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
      }
    }
  }
  static func digest(_ page: WikiPage) -> String {
    WikiStore.digest(Data((EmbeddingAssets.identity + "\n" + page.title + "\n" + page.body).utf8))
  }
  static func decodeVector(_ text: String) -> [Float]? {
    guard let data = Data(base64Encoded: text), data.count == 768 * 4 else { return nil }
    let values = data.withUnsafeBytes { bytes in
      (0..<768).map {
        Float(
          bitPattern: UInt32(
            littleEndian: bytes.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self)))
      }
    }
    let norm = values.reduce(Float(0)) { $0 + $1 * $1 }
    guard values.allSatisfy(\.isFinite), norm > 0.9, norm < 1.1 else { return nil }
    return values
  }
  func vector(_ id: String) throws -> [Float]? {
    guard let value = try db.query("SELECT vector FROM vectors WHERE id=?", [id]).first?.first
    else { return nil }
    return Self.decodeVector(value)
  }
  func saveVector(_ id: String, _ vector: [Float]) throws {
    guard vector.count == 768, vector.allSatisfy(\.isFinite) else {
      throw WikiError.invalid("embedding vector")
    }
    let norm = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
    guard norm > 0.01 else { throw WikiError.invalid("embedding norm") }
    var words = vector.map { ($0 / norm).bitPattern.littleEndian }
    let data = words.withUnsafeMutableBytes { Data($0) }
    try db.execute("INSERT OR REPLACE INTO vectors VALUES (?,?)", [id, data.base64EncodedString()])
  }
  func replace(_ page: WikiPage, passages: [SemanticPassage]) throws {
    let digest = Self.digest(page)
    try db.transaction {
      try db.execute("DELETE FROM passages WHERE slug=?", [page.slug])
      for p in passages {
        try db.execute(
          "INSERT OR IGNORE INTO passages VALUES (?,?,?,?)",
          [p.id, p.slug, digest, WikiJSON.encode(p)])
      }
      try db.execute(
        "INSERT OR REPLACE INTO indexed VALUES (?,?,?)", [page.slug, digest, String(page.revision)])
      try db.execute("DELETE FROM failures WHERE slug=?", [page.slug])
    }
  }
  func missing(_ pages: [WikiPage]) throws -> [WikiPage] {
    let indexed = Dictionary(
      uniqueKeysWithValues: try db.query("SELECT slug,digest FROM indexed").map { ($0[0], $0[1]) })
    return try pages.filter { page in
      if indexed[page.slug] != Self.digest(page) { return true }
      let rows = try db.query(
        "SELECT v.vector FROM passages p LEFT JOIN vectors v ON v.id=p.id WHERE p.slug=?",
        [page.slug])
      let invalid = rows.isEmpty || rows.contains { Self.decodeVector($0[0]) == nil }
      if !invalid {
        try db.execute(
          "UPDATE indexed SET revision=? WHERE slug=?", [String(page.revision), page.slug])
      }
      return invalid
    }
  }
  func prune(_ slugs: Set<String>) throws {
    for row in try db.query("SELECT slug FROM indexed") where !slugs.contains(row[0]) {
      try db.transaction {
        try db.execute("DELETE FROM passages WHERE slug=?", [row[0]])
        try db.execute("DELETE FROM indexed WHERE slug=?", [row[0]])
      }
    }
    try db.execute("DELETE FROM vectors WHERE id NOT IN (SELECT id FROM passages)")
    for row in try db.query("SELECT slug FROM failures") where !slugs.contains(row[0]) {
      try db.execute("DELETE FROM failures WHERE slug=?", [row[0]])
    }
  }
  func recordFailure(_ page: WikiPage) throws {
    try db.transaction {
      try db.execute(
        "INSERT OR REPLACE INTO failures VALUES (?,?,?)",
        [page.slug, String(page.revision), String(Date().timeIntervalSince1970)])
      // A now-unreadable original cannot remain a current search result.
      try db.execute("DELETE FROM passages WHERE slug=?", [page.slug])
      try db.execute("DELETE FROM indexed WHERE slug=?", [page.slug])
    }
  }
  func recentlyFailed(_ slug: String, revision: Int) throws -> Bool {
    guard
      let row = try db.query("SELECT revision,failed_at FROM failures WHERE slug=?", [slug]).first
    else { return false }
    return Int(row[0]) == revision && Date().timeIntervalSince1970 - (Double(row[1]) ?? 0) < 60
  }
  func failureCount(_ revisions: [String: Int]) throws -> Int {
    try db.query("SELECT slug,revision FROM failures").filter { revisions[$0[0]] == Int($0[1]) }
      .count
  }
  func coverage(_ revisions: [String: Int]) throws -> Int {
    let rows = try db.query(
      "SELECT i.slug,i.revision FROM indexed i WHERE EXISTS(SELECT 1 FROM passages p WHERE p.slug=i.slug) AND NOT EXISTS(SELECT 1 FROM passages p LEFT JOIN vectors v ON v.id=p.id WHERE p.slug=i.slug AND (v.vector IS NULL OR length(v.vector)<>4096))"
    )
    return rows.filter { revisions[$0[0]] == Int($0[1]) }.count
  }
  func matches(query: [Float], pages: [WikiPage]) throws -> [String: SemanticMatch] {
    try matches(
      query: query,
      revisions: Dictionary(uniqueKeysWithValues: pages.map { ($0.slug, $0.revision) }))
  }
  func matches(query: [Float], revisions: [String: Int]) throws -> [String: SemanticMatch] {
    let groups = try modalityMatches(query: query, revisions: revisions)
    var best = [String: SemanticMatch]()
    for group in groups.values {
      for (key, match) in group where match.similarity > (best[key]?.similarity ?? -.infinity) {
        best[key] = match
      }
    }
    return best
  }
  /// Gemma 2 places every modality in one normalized vector space. Rank its candidates
  /// by cosine; independent modality ranks would promote an unrelated singleton audio file.
  /// Retain 20 candidates per modality before the combined search applies its limit.
  func rankedMatches(query: [Float], revisions: [String: Int]) throws
    -> [(key: String, match: SemanticMatch)]
  {
    let groups = try modalityMatches(query: query, revisions: revisions)
    var evidence = [String: SemanticMatch]()
    for modality in groups.keys.sorted() {
      let group = groups[modality]!
      let ordered = group.keys.sorted {
        group[$0]!.similarity > group[$1]!.similarity
          || (group[$0]!.similarity == group[$1]!.similarity && $0 < $1)
      }
      for key in ordered.prefix(20) {
        if group[key]!.similarity > (evidence[key]?.similarity ?? -.infinity) {
          evidence[key] = group[key]!
        }
      }
    }
    return evidence.keys.sorted {
      evidence[$0]!.similarity > evidence[$1]!.similarity
        || (evidence[$0]!.similarity == evidence[$1]!.similarity && $0 < $1)
    }.map { ($0, evidence[$0]!) }
  }
  private func modalityMatches(query: [Float], revisions: [String: Int]) throws
    -> [String: [String: SemanticMatch]]
  {
    guard query.count == 768, query.allSatisfy(\.isFinite) else {
      throw WikiError.invalid("query vector")
    }
    var best = [String: [String: SemanticMatch]]()
    // ponytail: flat 768-dimensional scan for personal libraries; measure before introducing ANN storage.
    try db.transaction(readOnly: true) {
      var cursor = 0
      while true {
        let rows = try db.query(
          "SELECT p.slug,i.revision,p.data,v.vector FROM passages p JOIN vectors v ON v.id=p.id JOIN indexed i ON i.slug=p.slug AND i.digest=p.digest ORDER BY p.slug,p.id LIMIT 256 OFFSET \(cursor)"
        )
        guard !rows.isEmpty else { break }
        cursor += rows.count
        for row in rows {
          guard revisions[row[0]] == Int(row[1]) else { continue }
          guard let vector = Self.decodeVector(row[3]),
            let passage = try? WikiJSON.decoder().decode(
              SemanticPassage.self, from: Data(row[2].utf8))
          else {
            continue
          }
          var score: Float = 0
          vDSP_dotpr(query, 1, vector, 1, &score, 768)
          // Similarity ranks candidates; it does not establish answerability.
          let modality = passage.media?.kind ?? "text"
          if score.isFinite && score > (best[modality]?[row[0]]?.similarity ?? -.infinity) {
            best[modality, default: [:]][row[0]] = SemanticMatch(
              excerpt: passage.excerpt, heading: passage.heading, similarity: score,
              method: modality == "audio" ? "audio" : modality == "image" ? "visual" : "semantic",
              revision: revisions[row[0]]!, page: passage.media?.pageNumber ?? passage.pageNumber,
              modality: modality, startSeconds: passage.media?.startSeconds,
              endSeconds: passage.media?.endSeconds)
          }
        }
      }
    }
    return best
  }
}

public enum EmbeddingAssets {
  public static let modelHash = "2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135"
  public static let projectorHash =
    "c4a8a52691ecef40618438928bdf9e68379b854e24166f292592353db0aab64f"
  static let identity =
    modelHash + ":" + projectorHash + ":multimodal-v3:384:title80:prefix128:jpeg2048:audio20mono16k"
  static let cacheFilename =
    "embedding-" + WikiStore.digest(Data(identity.utf8)).prefix(16) + ".sqlite3"
  static let failureFilename =
    "runtime-failure-" + WikiStore.digest(Data(identity.utf8)).prefix(16) + ".json"
  static var disabled: Bool {
    ProcessInfo.processInfo.environment["GALPIUM_SEMANTIC_DISABLED"] == "1"
  }
  static var directory: URL {
    Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Embedding")
  }
  static var worker: URL {
    if let path = ProcessInfo.processInfo.environment["GALPIUM_EMBEDDER"] {
      return URL(fileURLWithPath: path)
    }
    return Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/galpium-embedder")
  }
  static var model: URL {
    if let path = ProcessInfo.processInfo.environment["GALPIUM_EMBEDDING_MODEL"] {
      return URL(fileURLWithPath: path)
    }
    return directory.appendingPathComponent("embeddinggemma-2-Q8_0.gguf")
  }
  static var projector: URL {
    if let path = ProcessInfo.processInfo.environment["GALPIUM_EMBEDDING_PROJECTOR"] {
      return URL(fileURLWithPath: path)
    }
    return directory.appendingPathComponent("mmproj-embeddinggemma-2-Q8_0.gguf")
  }
  static var runtime: URL {
    if let path = ProcessInfo.processInfo.environment["GALPIUM_EMBEDDING_RUNTIME"] {
      return URL(fileURLWithPath: path)
    }
    return directory.appendingPathComponent("runtime/llama-server")
  }
  public static var available: Bool {
    !disabled && FileManager.default.isExecutableFile(atPath: worker.path)
      && FileManager.default.isExecutableFile(atPath: runtime.path)
      && FileManager.default.fileExists(atPath: model.path)
      && FileManager.default.fileExists(atPath: projector.path)
  }
}

extension WikiStore {
  public func semanticStatus() -> SemanticStatus {
    let revisions = (try? semanticRevisions()) ?? [:]
    let pages = revisions.filter { !$0.key.hasPrefix("material:") }
    let materials = revisions.filter { $0.key.hasPrefix("material:") }
    guard let cache = try? SemanticCache(root: root), let indexed = try? cache.coverage(pages),
      let indexedMaterials = try? cache.coverage(materials)
    else {
      return SemanticStatus(
        state: EmbeddingAssets.available ? "unavailable" : "not_configured", indexedPages: 0,
        totalPages: pages.count, indexedMaterials: 0, totalMaterials: materials.count)
    }
    let failed =
      (try? Data(
        contentsOf: root.appendingPathComponent("search-cache/" + EmbeddingAssets.failureFilename)))
      .flatMap { try? JSONDecoder().decode(Double.self, from: $0) }
    let coolingDown = failed.map { Date().timeIntervalSince1970 - $0 < 30 } ?? false
    let failedMaterials = (try? cache.failureCount(materials)) ?? 0
    let failedPages = (try? cache.failureCount(pages)) ?? 0
    return SemanticStatus(
      state: !EmbeddingAssets.available
        ? "not_configured"
        : coolingDown
          ? "unavailable"
          : indexed == pages.count && indexedMaterials == materials.count
            ? "ready" : failedMaterials + failedPages > 0 ? "partial" : "warming",
      indexedPages: indexed, totalPages: pages.count, indexedMaterials: indexedMaterials,
      totalMaterials: materials.count, failedMaterials: failedMaterials, failedPages: failedPages)
  }
  public func scheduleSemanticIndex() {
    let status = semanticStatus()
    guard EmbeddingAssets.available, status.pending, status.state != "unavailable" else { return }
    let root = self.root
    DispatchQueue.global(qos: .utility).async {
      _ = try? EmbeddingClient(root: root).request(EmbeddingRequest(operation: "index"))
    }
  }
  public func hybridSearch(
    query: String, status: String = "active", tag: String? = nil, limit: Int = 100, offset: Int = 0
  ) throws -> HybridResult {
    _ = try WikiValidation.text(query, field: "query", bytes: 800, count: 200)
    guard limit > 0, limit <= 10000, offset >= 0 else { throw WikiError.invalid("pagination") }
    let lexical = try pageSummaries(status: status, tag: tag, query: query, limit: 10000)
    var semantic = [String: SemanticMatch]()
    var state =
      status == "active"
      ? semanticStatus() : SemanticStatus(state: "not_applicable", indexedPages: 0, totalPages: 0)
    if status == "active", EmbeddingAssets.available, state.totalPages > 0,
      try pageCount(status: status, tag: tag) > 0
    {
      do {
        let response = try EmbeddingClient(root: root).request(
          EmbeddingRequest(operation: "query", text: query))
        guard let vector = response.vector else { throw WikiError.storage("no query embedding") }
        // Re-read after inference: never return old content, removed tags or newly archived pages.
        let rows = try pageSummaries(status: status, tag: tag, limit: 10000)
        semantic = try SemanticCache(root: root).matches(
          query: vector,
          revisions: Dictionary(uniqueKeysWithValues: rows.map { ($0.slug, $0.revision) }))
        state = semanticStatus()
      } catch { state.state = "unavailable" }
    }
    let current = try pageSummaries(status: status, tag: tag, limit: 10000)
    let bySlug = Dictionary(uniqueKeysWithValues: current.map { ($0.slug, $0) })
    semantic = semantic.filter { bySlug[$0.key]?.revision == $0.value.revision }
    let validLexical = lexical.filter { bySlug[$0.slug]?.revision == $0.revision }
    let semanticOrder = semantic.keys.sorted {
      semantic[$0]!.similarity > semantic[$1]!.similarity
        || (semantic[$0]!.similarity == semantic[$1]!.similarity && $0 < $1)
    }
    let semanticCandidates = Array(semanticOrder.prefix(20))
    let semanticSet = Set(semanticCandidates)
    semantic = semantic.filter { semanticSet.contains($0.key) }
    var scores = [String: Double]()
    for list in [validLexical.map(\.slug), semanticCandidates] {
      for (i, slug) in list.enumerated() { scores[slug, default: 0] += 1 / Double(61 + i) }
    }
    let ordered = scores.keys.filter { bySlug[$0] != nil }.sorted {
      scores[$0]! > scores[$1]! || (scores[$0]! == scores[$1]! && $0 < $1)
    }
    let lexicalSlugs = Set(validLexical.map(\.slug))
    for slug in semantic.keys where lexicalSlugs.contains(slug) {
      semantic[slug]?.method = "hybrid"
    }
    let selected = ordered.dropFirst(min(offset, ordered.count)).prefix(limit).compactMap {
      slug -> PageSummary? in
      guard var item = bySlug[slug] else { return nil }
      if let match = semantic[slug] { item.excerpt = match.excerpt }
      return item
    }
    return HybridResult(items: selected, total: ordered.count, status: state, matches: semantic)
  }
}
