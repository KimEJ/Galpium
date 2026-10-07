import Foundation
import PDFKit

public struct WikiMaterial: Codable, Identifiable, Equatable, Sendable {
  enum CodingKeys: String, CodingKey {
    case id, title, kind, sourceSlug, url, status, createdAt, revision, originalHash
    case fileID = "fileId"
  }
  public var id: String
  public var title: String
  public var kind: String
  public var sourceSlug: String?
  public var fileID: String?
  public var url: String
  public var status: String
  public var createdAt: String
  public var revision: Int
  public var originalHash: String
  public static let audioExtensions: Set<String> = [
    "wav", "mp3", "m4a", "aac", "flac", "aiff", "aif", "caf",
  ]
  // Older libraries registered audio as an ordinary file. Interpret those records
  // without rewriting their original metadata or revision history.
  var effectiveKind: String {
    kind == "file"
      && Self.audioExtensions.contains(
        URL(fileURLWithPath: title).pathExtension.lowercased())
      ? "audio" : kind
  }
  public static func sourceID(_ slug: String) -> String {
    "s-" + WikiStore.digest(Data(slug.utf8)).prefix(30)
  }
  public static func fileID(_ id: String) -> String { "f-" + id }
}
public struct MaterialTextPage: Codable, Equatable, Sendable {
  public var number: Int
  public var text: String
}
public struct MaterialExtraction: Codable, Identifiable, Equatable, Sendable {
  enum CodingKeys: String, CodingKey {
    case id, originalHash, method, pages, textHash
    case materialID = "materialId"
  }
  public var id: String
  public var materialID: String
  public var originalHash: String
  public var method: String
  public var pages: [MaterialTextPage]
  public var textHash: String
}
public struct WikiCitation: Codable, Equatable, Identifiable, Sendable {
  enum CodingKeys: String, CodingKey {
    case id, originalHash, page, quote
    case materialID = "materialId"
    case extractionID = "extractionId"
  }
  public var id: String
  public var materialID: String
  public var originalHash: String
  public var extractionID: String
  public var page: Int
  public var quote: String
}
public struct MaterialReference: Codable, Sendable {
  public var kind: String
  public var id: String
  public var title: String
  public var historical: Bool
}

extension SQLite {
  static let materialSchema = """
    CREATE TABLE materials (id TEXT PRIMARY KEY, data TEXT NOT NULL CHECK(json_valid(data))) STRICT;
    CREATE TABLE material_extracts (id TEXT PRIMARY KEY, material_id TEXT NOT NULL REFERENCES materials(id), data TEXT NOT NULL CHECK(json_valid(data))) STRICT;
    CREATE INDEX material_extract_owner ON material_extracts(material_id);
    CREATE TABLE page_materials (page_slug TEXT NOT NULL REFERENCES pages(slug), material_id TEXT NOT NULL REFERENCES materials(id), PRIMARY KEY(page_slug,material_id)) STRICT;
    CREATE INDEX material_references ON page_materials(material_id,page_slug);
    DROP TRIGGER source_immutable_delete;
    CREATE TRIGGER source_immutable_delete BEFORE DELETE ON sources WHEN EXISTS(SELECT 1 FROM materials WHERE json_extract(data,'$.source_slug')=old.slug) BEGIN SELECT RAISE(ABORT,'immutable source'); END;
    CREATE TRIGGER extraction_immutable_update BEFORE UPDATE ON material_extracts BEGIN SELECT RAISE(ABORT,'immutable extraction'); END;
    CREATE TRIGGER page_writer_insert BEFORE INSERT ON pages WHEN json_type(new.data,'$.materials') IS NULL BEGIN SELECT RAISE(ABORT,'update Galpium before writing'); END;
    CREATE TRIGGER page_writer_update BEFORE UPDATE ON pages WHEN json_type(new.data,'$.materials') IS NULL BEGIN SELECT RAISE(ABORT,'update Galpium before writing'); END;
    """
  func registerMaterial(_ material: WikiMaterial) throws {
    if let slug = material.sourceSlug {
      let aliases = try query(
        "SELECT id FROM materials WHERE json_extract(data,'$.source_slug')=?", [slug])
      guard aliases.allSatisfy({ $0[0] == material.id }) else {
        throw WikiError.invalid("duplicate original alias")
      }
    }
    try execute(
      "INSERT INTO materials VALUES (?,?) ON CONFLICT(id) DO NOTHING",
      [material.id, WikiJSON.encode(material)])
  }
  func registerSourceMaterial(_ source: WikiSource) throws {
    try registerMaterial(
      WikiMaterial(
        id: WikiMaterial.sourceID(source.slug), title: source.title, kind: "text",
        sourceSlug: source.slug, url: source.url, status: "active", createdAt: source.createdAt,
        revision: 1, originalHash: source.sha256 ?? WikiStore.digest(Data(source.body.utf8))))
  }
  func registerFileMaterial(_ item: WikiAttachment) throws {
    let ext = URL(fileURLWithPath: item.name).pathExtension.lowercased()
    let kind =
      ext == "pdf"
      ? "pdf"
      : ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"].contains(ext)
        ? "image"
        : WikiMaterial.audioExtensions.contains(ext)
          ? "audio" : ["txt", "md", "markdown"].contains(ext) ? "text" : "file"
    try registerMaterial(
      WikiMaterial(
        id: WikiMaterial.fileID(item.id), title: item.name, kind: kind, fileID: item.id, url: "",
        status: "active", createdAt: item.createdAt, revision: 1, originalHash: item.sha256))
  }
}

extension WikiStore {
  public func material(_ id: String) throws -> WikiMaterial {
    _ = try WikiValidation.slug(id)
    guard let row = try db.query("SELECT data FROM materials WHERE id=?", [id]).first else {
      throw WikiError.notFound("material")
    }
    var item = try WikiJSON.decoder().decode(WikiMaterial.self, from: Data(row[0].utf8))
    item.kind = item.effectiveKind
    return item
  }
  public func materialForSource(_ slug: String) throws -> WikiMaterial {
    guard
      let row = try db.query(
        "SELECT data FROM materials WHERE json_extract(data,'$.source_slug')=?", [slug]
      ).first
    else { throw WikiError.notFound("material") }
    return try WikiJSON.decoder().decode(WikiMaterial.self, from: Data(row[0].utf8))
  }
  public func materials(status: String = "active", kind: String = "all", query: String = "") throws
    -> [WikiMaterial]
  {
    guard ["all", "active", "archived"].contains(status),
      ["all", "text", "pdf", "image", "audio", "file"].contains(kind)
    else { throw WikiError.invalid("material filter") }
    let items = try db.query(
      "SELECT data FROM materials ORDER BY json_extract(data,'$.created_at') DESC,id"
    ).map {
      var item = try WikiJSON.decoder().decode(WikiMaterial.self, from: Data($0[0].utf8))
      item.kind = item.effectiveKind
      return item
    }
    return items.filter {
      (status == "all" || $0.status == status) && (kind == "all" || $0.kind == kind)
        && (query.isEmpty || $0.title.localizedStandardContains(query))
    }
  }
  @discardableResult
  public func addTextMaterial(title: String, body: String, url: String = "") throws -> WikiMaterial
  {
    let source = try ingest(
      slug: "text-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
      title: title, body: body, url: url)
    return try materialForSource(source.slug)
  }
  public func materialFileURL(_ material: WikiMaterial) throws -> URL? {
    try material.fileID.map { attachmentURL(try attachment($0)) }
  }
  public func extraction(_ id: String) throws -> MaterialExtraction {
    guard let row = try db.query("SELECT data FROM material_extracts WHERE id=?", [id]).first else {
      throw WikiError.notFound("extraction")
    }
    return try WikiJSON.decoder().decode(MaterialExtraction.self, from: Data(row[0].utf8))
  }
  public func materialExtraction(_ id: String) throws -> MaterialExtraction? {
    let item = try material(id)
    try verifyOriginal(item)
    if let row = try db.query(
      "SELECT data FROM material_extracts WHERE material_id=? ORDER BY rowid DESC LIMIT 1", [id]
    ).first {
      return try WikiJSON.decoder().decode(MaterialExtraction.self, from: Data(row[0].utf8))
    }
    var pages = [MaterialTextPage]()
    let method: String
    if let slug = item.sourceSlug {
      pages = [MaterialTextPage(number: 1, text: try source(slug).body)]
      method = "original-text-v1"
    } else if let file = try materialFileURL(item), item.kind == "text" {
      guard
        let text = String(data: try Data(contentsOf: file, options: .mappedIfSafe), encoding: .utf8)
      else { throw WikiError.invalid("UTF-8 text") }
      pages = [MaterialTextPage(number: 1, text: text)]
      method = "utf8-v1"
    } else if let file = try materialFileURL(item), item.kind == "pdf" {
      guard let pdf = PDFDocument(url: file), !pdf.isLocked else { throw WikiError.invalid("PDF") }
      method = "pdfkit-v1"
      var count = 0
      for index in 0..<pdf.pageCount {
        try Task.checkCancellation()
        let text = pdf.page(at: index)?.string ?? ""
        count += text.utf8.count
        guard count <= 16 * 1024 * 1024 else { throw WikiError.invalid("extracted text (16 MiB)") }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          pages.append(MaterialTextPage(number: index + 1, text: text))
        }
      }
    } else {
      return nil
    }
    guard pages.reduce(0, { $0 + $1.text.utf8.count }) <= 16 * 1024 * 1024 else {
      throw WikiError.invalid("extracted text (16 MiB)")
    }
    let hash = WikiStore.digest(try WikiJSON.encoder().encode(pages))
    let value = MaterialExtraction(
      id: WikiStore.digest(Data((id + item.originalHash + method + hash).utf8)), materialID: id,
      originalHash: item.originalHash, method: method, pages: pages, textHash: hash)
    try db.execute(
      "INSERT INTO material_extracts VALUES (?,?,?) ON CONFLICT(id) DO NOTHING",
      [value.id, id, WikiJSON.encode(value)])
    return value
  }
  @discardableResult
  public func importMaterial(data: Data, name: String, url: String = "") throws -> WikiMaterial {
    _ = try WikiValidation.provenanceURL(url)
    // Reuse identical retries with the same provenance, never merge distinct origins.
    let hash = Self.digest(data)
    if let existing = try materials(status: "all").first(where: {
      $0.fileID != nil && $0.originalHash == hash && $0.title == name && $0.url == url
    }) {
      return existing
    }
    let existingBlob = try attachments().first {
      $0.sha256 == hash
        && URL(fileURLWithPath: $0.name).pathExtension == URL(fileURLWithPath: name).pathExtension
    }
    let blob = try existingBlob ?? attach(data: data, name: name)
    return try db.transaction {
      var item = try material(WikiMaterial.fileID(blob.id))
      if existingBlob != nil {
        item.id = "m-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        item.createdAt = WikiJSON.now()
      }
      item.title = name
      item.url = url
      if existingBlob != nil {
        try db.registerMaterial(item)
      } else {
        try db.execute("UPDATE materials SET data=? WHERE id=?", [WikiJSON.encode(item), item.id])
      }
      return item
    }
  }
  public func updateMaterial(
    _ id: String, title: String? = nil, status: String? = nil, expectedRevision: Int
  ) throws -> WikiMaterial {
    try db.transaction {
      var item = try material(id)
      guard item.revision == expectedRevision else { throw WikiError.conflict(item.revision) }
      if let title {
        let originalExtension = URL(fileURLWithPath: item.title).pathExtension
        item.title = try WikiValidation.text(
          title, field: "material title", bytes: 1024, count: 255)
        if item.fileID != nil {
          guard
            originalExtension == URL(fileURLWithPath: title).pathExtension
          else { throw WikiError.invalid("file extension") }
        }
      }
      if let status {
        guard ["active", "archived"].contains(status) else { throw WikiError.invalid("status") }
        item.status = status
      }
      item.revision += 1
      try db.execute("UPDATE materials SET data=? WHERE id=?", [WikiJSON.encode(item), id])
      return item
    }
  }
  public func materialIDs(in page: WikiPage) throws -> Set<String> {
    var ids = Set(
      page.materials + page.citations.map(\.materialID) + Markdown.materialIDs(page.body))
    for slug in page.sources + Markdown.sourceIDs(page.body) {
      if let m = try? materialForSource(slug) { ids.insert(m.id) }
    }
    for id in Markdown.attachmentIDs(page.body) { ids.insert(WikiMaterial.fileID(id)) }
    return ids
  }
  private func materialReferenceMap() throws -> [String: [MaterialReference]] {
    let items = try materials(status: "all")
    let known = Set(items.map(\.id))
    let sourceIDs = Dictionary(
      uniqueKeysWithValues: items.compactMap { item in item.sourceSlug.map { ($0, item.id) } })
    var owners = [String: [String: MaterialReference]]()
    func ids(_ body: String) -> Set<String> {
      Set(
        Markdown.materialIDs(body) + Markdown.attachmentIDs(body).map(WikiMaterial.fileID)
          + Markdown.sourceIDs(body).compactMap { sourceIDs[$0] })
    }
    let rows = try db.query(
      "SELECT 'current',data FROM pages UNION ALL SELECT 'history',data FROM revisions UNION ALL SELECT 'draft',data FROM drafts"
    )
    for row in rows {
      let page =
        row[0] == "draft"
        ? try WikiJSON.decoder().decode(WikiDraft.self, from: Data(row[1].utf8)).page
        : try WikiJSON.decoder().decode(WikiPage.self, from: Data(row[1].utf8))
      let targets = ids(page.body).union(
        page.materials + page.citations.map(\.materialID)
          + page.sources.compactMap { sourceIDs[$0] })
      let key = "page:" + page.slug
      let historical = row[0] == "history"
      for id in targets.intersection(known) where owners[id]?[key] == nil || !historical {
        owners[id, default: [:]][key] = MaterialReference(
          kind: "page", id: page.slug,
          title: page.title.isEmpty ? localized("제목 없는 초안") : page.title, historical: historical)
      }
    }
    for source in try sources() {
      guard let ownerID = sourceIDs[source.slug] else { continue }
      for target in ids(source.body).intersection(known) where target != ownerID {
        owners[target, default: [:]]["material:" + ownerID] = MaterialReference(
          kind: "material", id: ownerID,
          title: items.first { $0.id == ownerID }?.title ?? source.title, historical: false)
      }
    }
    return owners.mapValues { $0.values.sorted { $0.title < $1.title } }
  }
  public func materialLinkCounts() throws -> [String: Int] {
    try materialReferenceMap().mapValues { $0.count }
  }
  public func materialReferences(_ id: String) throws -> [MaterialReference] {
    _ = try material(id)
    return try materialReferenceMap()[id] ?? []
  }
  public func deleteMaterial(_ id: String, expectedRevision: Int) throws {
    var original: URL?
    var trashed: URL?
    do {
      try db.transaction {
        let item = try material(id)
        guard item.revision == expectedRevision else { throw WikiError.conflict(item.revision) }
        guard try materialReferences(id).isEmpty else { throw WikiError.attachmentInUse }
        let shared = try materials(status: "all").filter {
          $0.id != id && $0.fileID != nil && $0.fileID == item.fileID
        }
        try db.execute("DELETE FROM material_extracts WHERE material_id=?", [id])
        try db.execute("DELETE FROM materials WHERE id=?", [id])
        if let slug = item.sourceSlug { try db.execute("DELETE FROM sources WHERE slug=?", [slug]) }
        if let fileID = item.fileID, shared.isEmpty {
          original = try materialFileURL(item)
          trashed = try trashAttachment(fileID)
        }
      }
    } catch {
      if let original, let trashed, !FileManager.default.fileExists(atPath: original.path) {
        try FileManager.default.moveItem(at: trashed, to: original)
      }
      throw error
    }
  }
  func verifyOriginal(_ item: WikiMaterial) throws {
    if let file = try materialFileURL(item) {
      guard Self.digest(try Data(contentsOf: file, options: .mappedIfSafe)) == item.originalHash
      else { throw WikiError.invalid("original checksum") }
    }
    if let slug = item.sourceSlug {
      guard Self.digest(Data(try source(slug).body.utf8)) == item.originalHash else {
        throw WikiError.invalid("original checksum")
      }
    }
  }
  public func validateCitation(_ citation: WikiCitation) throws {
    try verifyOriginal(material(citation.materialID))
    try validateCitationPayload(citation)
  }
  func validateCitationPayload(_ citation: WikiCitation) throws {
    let item = try material(citation.materialID)
    let text = try extraction(citation.extractionID)
    guard citation.originalHash == item.originalHash, text.materialID == item.id,
      text.originalHash == item.originalHash,
      !citation.quote.isEmpty, citation.quote.utf8.count <= 8000,
      text.pages.contains(where: { $0.number == citation.page && $0.text.contains(citation.quote) })
    else { throw WikiError.invalid("citation evidence") }
  }
  public func makeCitation(materialID: String, page: Int, quote: String, id: String) throws
    -> WikiCitation
  {
    let item = try material(materialID)
    guard let text = try materialExtraction(item.id) else {
      throw WikiError.invalid("material has no text")
    }
    let value = WikiCitation(
      id: try WikiValidation.slug(id), materialID: item.id, originalHash: item.originalHash,
      extractionID: text.id, page: page, quote: quote)
    try validateCitation(value)
    return value
  }
}

public struct MaterialSearchResult: Sendable {
  public var items: [WikiMaterial]
  public var matches: [String: SemanticMatch]
  public var state: String
}
extension WikiStore {
  func semanticDocument(_ key: String) throws -> WikiPage {
    guard key.hasPrefix("material:") else { return try page(key) }
    let item = try material(String(key.dropFirst(9)))
    guard item.status == "active", ["text", "pdf", "image", "audio"].contains(item.kind) else {
      throw WikiError.notFound("searchable material")
    }
    try verifyOriginal(item)
    let pages = try materialExtraction(item.id)?.pages ?? []
    guard !pages.isEmpty || item.kind != "text" else {
      throw WikiError.notFound("searchable material")
    }
    return WikiPage(
      slug: key, title: item.title,
      body: pages.isEmpty
        ? ""
        : pages.map { "## Page \($0.number)\n\n" + $0.text }.joined(separator: "\n\n"),
      revision: item.revision)
  }
  func semanticDocuments() throws -> [WikiPage] {
    var docs = try pages()
    for item in try materials() where ["text", "pdf", "image", "audio"].contains(item.kind) {
      if let doc = try? semanticDocument("material:" + item.id) { docs.append(doc) }
    }
    return docs
  }
  func semanticRevisions() throws -> [String: Int] {
    var result = Dictionary(
      uniqueKeysWithValues: try db.query("SELECT slug,revision FROM pages WHERE status='active'")
        .map { ($0[0], Int($0[1]) ?? 0) })
    for item in try materials() where ["text", "pdf", "image", "audio"].contains(item.kind) {
      if item.kind != "text" {
        result["material:" + item.id] = item.revision
        continue
      }
      let empty = try db.query(
        "SELECT 1 FROM material_extracts WHERE material_id=? AND json_array_length(json_extract(data,'$.pages'))=0 LIMIT 1",
        [item.id])
      if empty.isEmpty { result["material:" + item.id] = item.revision }
    }
    return result
  }
  public func searchMaterials(query: String, status: String = "active", kind: String = "all") throws
    -> MaterialSearchResult
  {
    _ = try WikiValidation.text(query, field: "query", bytes: 800, count: 200, empty: true)
    let items = try materials(status: status, kind: kind)
    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return MaterialSearchResult(items: items, matches: [:], state: "ready")
    }
    let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
    var lexical = [String]()
    for item in items {
      let pages = (try? materialExtraction(item.id))?.pages ?? []
      let text = ([item.title, item.url] + pages.map(\.text)).joined(separator: "\n")
      if words.allSatisfy({ text.localizedStandardContains($0) }) { lexical.append(item.id) }
    }
    var matches = [String: SemanticMatch]()
    var semanticCandidates = [String]()
    var state = semanticStatus().state
    if status == "active", EmbeddingAssets.available, !items.isEmpty {
      do {
        let response = try EmbeddingClient(root: root).request(
          EmbeddingRequest(operation: "query", text: query))
        if let vector = response.vector {
          let fresh = try materials(status: status, kind: kind)
          let versions = Dictionary(
            uniqueKeysWithValues: fresh.map { ("material:" + $0.id, $0.revision) })
          let semantic = try SemanticCache(root: root).rankedMatches(
            query: vector, revisions: versions)
          for (key, match) in semantic {
            let id = String(key.dropFirst(9))
            matches[id] = match
            semanticCandidates.append(id)
          }
        }
        state = semanticStatus().state
      } catch { state = "unavailable" }
    }
    let fresh = try materials(status: status, kind: kind)
    let byID = Dictionary(uniqueKeysWithValues: fresh.map { ($0.id, $0) })
    let originalRevisions = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.revision) })
    let currentLexical = lexical.filter { byID[$0]?.revision == originalRevisions[$0] }
    let currentSemantic = semanticCandidates.filter {
      guard let item = byID[$0] else { return false }
      return matches[$0]?.revision == item.revision
    }
    var scores = [String: Double]()
    for list in [currentLexical, Array(currentSemantic.prefix(20))] {
      for (rank, id) in list.enumerated() { scores[id, default: 0] += 1 / Double(61 + rank) }
    }
    let ordered = scores.keys.sorted {
      scores[$0]! > scores[$1]! || (scores[$0] == scores[$1] && $0 < $1)
    }
    return MaterialSearchResult(
      items: ordered.compactMap { byID[$0] },
      matches: matches.filter { byID[$0.key]?.revision == $0.value.revision }, state: state)
  }
}
