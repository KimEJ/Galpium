import CryptoKit
import Foundation

public final class WikiStore: @unchecked Sendable {
  public let root: URL
  let db: SQLite
  public static var defaultRoot: URL {
    if let path = ProcessInfo.processInfo.environment["GALPIUM_LIBRARY"], !path.isEmpty {
      return URL(fileURLWithPath: path, isDirectory: true)
    }
    if let data = try? Data(contentsOf: libraryLocationFile),
      let path = try? JSONDecoder().decode(String.self, from: data), path.hasPrefix("/")
    {
      return URL(fileURLWithPath: path, isDirectory: true)
    }
    return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Galpium", isDirectory: true)
  }
  public static var libraryLocationFile: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Galpium/library-location.json")
  }
  public static func rememberLibrary(_ root: URL) throws {
    let file = libraryLocationFile
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try JSONEncoder().encode(root.path).write(to: file, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
  }
  public init(root: URL = WikiStore.defaultRoot) throws {
    self.root = URL(fileURLWithPath: canonicalLibraryPath(root), isDirectory: true)
    try FileManager.default.createDirectory(
      at: self.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try FileManager.default.createDirectory(
      at: self.root.appendingPathComponent("attachments"), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    db = try SQLite(url: self.root.appendingPathComponent("wiki.sqlite3"))
    for name in ["wiki.sqlite3", "wiki.sqlite3-wal", "wiki.sqlite3-shm"] {
      let path = self.root.appendingPathComponent(name).path
      if FileManager.default.fileExists(atPath: path) {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
      }
    }
  }
  public var changeToken: String { (try? db.query("PRAGMA data_version").first?.first) ?? "" }
  private func decode<T: Decodable>(_ rows: [[String]], as type: T.Type) throws -> [T] {
    try rows.map { try WikiJSON.decoder().decode(type, from: Data($0[0].utf8)) }
  }
  public func sources(query: String = "", limit: Int? = nil, offset: Int = 0) throws -> [WikiSource]
  {
    let filter = try sourceFilter(query)
    return try decode(
      db.query(
        "SELECT s.data FROM sources s WHERE " + filter.0 + " ORDER BY s.created_at DESC,s.slug"
          + pagination(limit, offset), filter.1), as: WikiSource.self)
  }
  public func source(_ slug: String) throws -> WikiSource {
    guard
      let value = try decode(
        db.query("SELECT data FROM sources WHERE slug=?", [WikiValidation.slug(slug)]),
        as: WikiSource.self
      ).first
    else { throw WikiError.notFound("source: \(slug)") }
    return value
  }
  public func pages(
    status: String = "active", tag: String? = nil, query: String = "", limit: Int? = nil,
    offset: Int = 0
  ) throws
    -> [WikiPage]
  {
    let filter = try pageFilter(status: status, tag: tag, query: query)
    return try decode(
      db.query(
        "SELECT p.data FROM pages p WHERE " + filter.0
          + " ORDER BY p.pinned DESC,p.updated_at DESC,p.slug" + pagination(limit, offset), filter.1
      ), as: WikiPage.self)
  }
  private func pagination(_ limit: Int?, _ offset: Int) throws -> String {
    guard offset >= 0, limit == nil || limit! > 0 else { throw WikiError.invalid("pagination") }
    return " LIMIT \(limit ?? -1) OFFSET \(offset)"
  }
  private func textFilter(_ query: String, alias: String, index: String) throws -> (
    String, [String]
  ) {
    let query = try WikiValidation.text(query, field: "query", bytes: 800, count: 200, empty: true)
      .lowercased()
    let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
    let indexed = words.filter {
      $0.unicodeScalars.count >= 3
        && $0.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }
    var clauses = ["1=1"]
    var values = [String]()
    if !indexed.isEmpty {
      clauses.append("\(alias).slug IN (SELECT slug FROM \(index) WHERE \(index) MATCH ?)")
      values.append(indexed.map { "\"" + $0 + "\"" }.joined(separator: " AND "))
    }
    for word in words {
      clauses.append("instr(\(alias).search_text,?)>0")
      values.append(word)
    }
    return (clauses.joined(separator: " AND "), values)
  }
  private func sourceFilter(_ query: String) throws -> (String, [String]) {
    try textFilter(query, alias: "s", index: "source_search")
  }
  private func pageFilter(status: String, tag: String?, query: String) throws -> (String, [String])
  {
    guard ["active", "archived", "all"].contains(status) else { throw WikiError.invalid("status") }
    var filter = try textFilter(query, alias: "p", index: "page_search")
    if status != "all" {
      filter.0 += " AND p.status=?"
      filter.1.append(status)
    }
    if let tag {
      filter.0 += " AND EXISTS(SELECT 1 FROM page_tags t WHERE t.page_slug=p.slug AND t.tag=?)"
      filter.1.append(tag.precomposedStringWithCanonicalMapping)
    }
    return filter
  }
  public func pageCount(status: String = "active", tag: String? = nil, query: String = "") throws
    -> Int
  {
    let filter = try pageFilter(status: status, tag: tag, query: query)
    return Int(try db.query("SELECT count(*) FROM pages p WHERE " + filter.0, filter.1)[0][0]) ?? 0
  }
  public func sourceCount(query: String = "") throws -> Int {
    let filter = try sourceFilter(query)
    return Int(try db.query("SELECT count(*) FROM sources s WHERE " + filter.0, filter.1)[0][0])
      ?? 0
  }
  public func tags(status: String = "active") throws -> [String] {
    guard ["active", "archived", "all"].contains(status) else { throw WikiError.invalid("status") }
    return try db.query(
      "SELECT DISTINCT t.tag FROM page_tags t JOIN pages p ON p.slug=t.page_slug"
        + (status == "all" ? "" : " WHERE p.status=?") + " ORDER BY t.tag",
      status == "all" ? [] : [status]
    ).map { $0[0] }
  }
  public func pageSummaries(
    status: String = "active", tag: String? = nil, query: String = "", limit: Int = 100,
    offset: Int = 0
  ) throws -> [PageSummary] {
    let filter = try pageFilter(status: status, tag: tag, query: query)
    return try decode(
      db.query(
        "SELECT json_object('slug',p.slug,'title',p.title,'excerpt',substr(p.body,1,240),'sources',json_extract(p.data,'$.sources'),'tags',json_extract(p.data,'$.tags'),'pinned',json(CASE p.pinned WHEN 1 THEN 'true' ELSE 'false' END),'status',p.status,'revision',p.revision,'created_at',p.created_at,'updated_at',p.updated_at) FROM pages p WHERE "
          + filter.0 + " ORDER BY p.pinned DESC,p.updated_at DESC,p.slug"
          + pagination(limit, offset), filter.1), as: PageSummary.self)
  }
  public func sourceSummaries(query: String = "", limit: Int = 100, offset: Int = 0) throws
    -> [SourceSummary]
  {
    let filter = try sourceFilter(query)
    return try decode(
      db.query(
        "SELECT json_object('slug',s.slug,'title',s.title,'excerpt',substr(s.body,1,240),'created_at',s.created_at) FROM sources s WHERE "
          + filter.0 + " ORDER BY s.created_at DESC,s.slug" + pagination(limit, offset), filter.1),
      as: SourceSummary.self)
  }
  public func selectedSourceSummaries(_ slugs: [String]) throws -> [SourceSummary] {
    guard !slugs.isEmpty else { return [] }
    let keys = try slugs.map(WikiValidation.slug)
    let placeholders = Array(repeating: "?", count: keys.count).joined(separator: ",")
    return try decode(
      db.query(
        "SELECT json_object('slug',slug,'title',title,'excerpt',substr(body,1,240),'created_at',created_at) FROM sources WHERE slug IN (\(placeholders)) ORDER BY title,slug",
        keys), as: SourceSummary.self)
  }
  public func page(_ slug: String, revision: Int? = nil) throws -> WikiPage {
    let slug = try WikiValidation.slug(slug)
    let rows: [[String]]
    if let revision {
      guard revision > 0 else { throw WikiError.invalid("revision") }
      rows = try db.query(
        "SELECT data FROM revisions WHERE slug=? AND revision=?", [slug, String(revision)])
    } else {
      rows = try db.query("SELECT data FROM pages WHERE slug=?", [slug])
    }
    guard let value = try decode(rows, as: WikiPage.self).first else {
      throw WikiError.notFound("page: \(slug)")
    }
    return value
  }
  public func history(_ slug: String, limit: Int? = nil, offset: Int = 0) throws -> [WikiPage] {
    _ = try page(slug)
    return try decode(
      db.query(
        "SELECT data FROM revisions WHERE slug=? ORDER BY revision DESC"
          + pagination(limit, offset), [slug]),
      as: WikiPage.self)
  }
  public func historyCount(_ slug: String) throws -> Int {
    _ = try page(slug)
    return Int(try db.query("SELECT count(*) FROM revisions WHERE slug=?", [slug])[0][0]) ?? 0
  }
  public func ingest(slug: String, title: String, body: String, url: String = "") throws
    -> WikiSource
  {
    let source = WikiSource(
      slug: try WikiValidation.slug(slug),
      title: try WikiValidation.text(title, field: "title", bytes: 720, count: 180),
      body: try WikiValidation.text(body, field: "source body", bytes: 256 * 1024, multiline: true),
      url: try WikiValidation.provenanceURL(url), createdAt: WikiJSON.now(),
      sha256: Self.digest(Data(body.utf8)))
    return try db.transaction {
      if let row = try db.query("SELECT data FROM sources WHERE slug=?", [source.slug]).first {
        let existing = try WikiJSON.decoder().decode(WikiSource.self, from: Data(row[0].utf8))
        guard
          existing.title == source.title && existing.body == source.body
            && existing.url == source.url
        else { throw WikiError.immutable }
        return existing
      }
      try db.insertSource(source)
      try log("ingest", slug: source.slug)
      return source
    }
  }
  func validate(_ input: WikiPage) throws -> WikiPage {
    var value = input
    value.slug = try WikiValidation.slug(value.slug)
    value.title = try WikiValidation.text(value.title, field: "title", bytes: 720, count: 180)
    value.body = try WikiValidation.text(
      value.body, field: "body", bytes: 64 * 1024, multiline: true)
    value.changeNote = try WikiValidation.text(
      value.changeNote, field: "change_note", bytes: 2000, count: 500, empty: true)
    guard value.sources.count <= 100, value.materials.count <= 100, value.citations.count <= 100,
      value.tags.count <= 20
    else {
      throw WikiError.invalid("sources / tags")
    }
    value.sources = try Array(Set(value.sources.map(WikiValidation.slug))).sorted()
    value.tags = try Array(
      Set(value.tags.map { try WikiValidation.text($0, field: "tag", bytes: 160, count: 40) })
    ).sorted()
    for slug in value.sources { _ = try materialForSource(slug) }
    value.materials = try Array(Set(value.materials.map(WikiValidation.slug))).sorted()
    for id in try materialIDs(in: value) { _ = try material(id) }
    let notes = Markdown.footnotes(value.body)
    guard Set(notes.map(\.id)).count == notes.count else {
      throw WikiError.invalid("duplicate footnote")
    }
    value.citations = value.citations.filter { citation in notes.contains { $0.id == citation.id } }
    guard Set(value.citations.map(\.id)).count == value.citations.count else {
      throw WikiError.invalid("duplicate citation")
    }
    var checkedOriginals = Set<String>()
    for citation in value.citations {
      if checkedOriginals.insert(citation.materialID).inserted {
        try verifyOriginal(material(citation.materialID))
      }
      try validateCitationPayload(citation)
      guard let note = notes.first(where: { $0.id == citation.id }),
        Markdown.materialIDs(note.text).contains(citation.materialID)
      else { throw WikiError.invalid("citation footnote") }
      let displayedQuote = note.text.components(separatedBy: "\n").filter { $0.hasPrefix("> ") }.map
      { String($0.dropFirst(2)) }.joined(separator: "\n")
      guard displayedQuote == citation.quote else {
        throw WikiError.invalid("citation quote mismatch")
      }

    }
    return value
  }
  public func upsert(_ input: WikiPage, expectedRevision: Int, preserveOriginal: Bool = false)
    throws -> WikiPage
  {
    guard expectedRevision >= 0 else { throw WikiError.invalid("expected_revision") }
    return try db.transaction {
      var value = input
      if preserveOriginal && value.sources.isEmpty {
        let original = try ingestInsideTransaction(title: value.title, body: value.body)
        value.sources = [original.slug]
      }
      value = try validate(value)
      value.status = "active"
      let current = try decode(
        db.query("SELECT data FROM pages WHERE slug=?", [value.slug]), as: WikiPage.self
      ).first
      if (current?.revision ?? 0) != expectedRevision {
        if let current, current.revision == expectedRevision + 1 && current.sameContent(as: value) {
          return current
        }
        throw WikiError.conflict(current?.revision ?? 0)
      }
      if let current, current.sameContent(as: value) { return current }
      try validateNewAttachmentReferences(value.body, previous: current?.body ?? "")
      value.revision = expectedRevision + 1
      value.operation = current == nil ? "create" : "edit"
      value.createdAt = current?.createdAt ?? WikiJSON.now()
      value.updatedAt = WikiJSON.now()
      value.restoredFromRevision = nil
      value.patchFingerprint = nil
      try commit(value, action: "upsert")
      return value
    }
  }
  private func ingestInsideTransaction(title: String, body: String) throws -> WikiSource {
    let title = try WikiValidation.text(title, field: "title", bytes: 720, count: 180)
    let body = try WikiValidation.text(body, field: "body", bytes: 64 * 1024, multiline: true)
    let hash = Self.digest(Data((title + "\n" + body).utf8))
    let slug = "note-" + String(hash.prefix(24))
    if let row = try db.query("SELECT data FROM sources WHERE slug=?", [slug]).first {
      return try WikiJSON.decoder().decode(WikiSource.self, from: Data(row[0].utf8))
    }
    let source = WikiSource(
      slug: slug, title: title, body: body, url: "", createdAt: WikiJSON.now(),
      sha256: Self.digest(Data(body.utf8)))
    try db.insertSource(source)
    try log("ingest", slug: slug)
    return source
  }
  private func commit(_ value: WikiPage, action: String) throws {
    let data = try WikiJSON.encode(value)
    try db.writePage(value, data: data)
    try db.execute(
      "INSERT INTO revisions(slug,revision,data) VALUES (?,?,?)",
      [value.slug, String(value.revision), data])
    try log(action, slug: value.slug, revision: value.revision)
  }
  public func archive(_ slug: String, expectedRevision: Int) throws -> WikiPage {
    try db.transaction {
      var current = try page(slug)
      if current.status == "archived",
        [current.revision, current.revision - 1].contains(expectedRevision)
      {
        return current
      }
      guard expectedRevision == current.revision else { throw WikiError.conflict(current.revision) }
      current.revision += 1
      current.status = "archived"
      current.operation = "archive"
      current.updatedAt = WikiJSON.now()
      current.changeNote = ""
      current.patchFingerprint = nil
      current.restoredFromRevision = nil
      try commit(current, action: "archive")
      return current
    }
  }
  public func restore(_ slug: String, revision: Int, expectedRevision: Int) throws -> WikiPage {
    try db.transaction {
      let current = try page(slug)
      if current.revision == expectedRevision + 1 && current.operation == "restore"
        && current.restoredFromRevision == revision
      {
        return current
      }
      guard current.revision == expectedRevision else { throw WikiError.conflict(current.revision) }
      var value = try page(slug, revision: revision)
      value.revision = current.revision + 1
      value.status = "active"
      value.operation = "restore"
      value.restoredFromRevision = revision
      value.patchFingerprint = nil
      value.updatedAt = WikiJSON.now()
      value.changeNote = localized("r%ld 복원", revision)
      try commit(value, action: "restore")
      return value
    }
  }
  public func patch(
    _ slug: String, expectedRevision: Int, replacements: [TextReplacement], note: String = ""
  ) throws -> WikiPage {
    guard expectedRevision >= 1, (1...20).contains(replacements.count) else {
      throw WikiError.invalid("replacements")
    }
    let fingerprint = Self.digest(
      try WikiJSON.encoder().encode(replacements) + Data("\(slug):\(expectedRevision):\(note)".utf8)
    )
    return try db.transaction {
      var value = try page(slug)
      if value.revision == expectedRevision + 1 && value.patchFingerprint == fingerprint {
        return value
      }
      guard value.revision == expectedRevision else { throw WikiError.conflict(value.revision) }
      guard value.status == "active" else { throw WikiError.invalid("archived page") }
      let previous = value.body
      value.body = try TextTools.replace(value.body, replacements: replacements)
      value.changeNote = note
      value = try validate(value)
      try validateNewAttachmentReferences(value.body, previous: previous)
      if value.body == (try page(slug)).body { return value }
      value.revision += 1
      value.operation = "edit"
      value.updatedAt = WikiJSON.now()
      value.patchFingerprint = fingerprint
      value.restoredFromRevision = nil
      try commit(value, action: "patch")
      return value
    }
  }
  public func backlinks(to slug: String) throws -> [WikiPage] {
    try decode(
      db.query(
        "SELECT p.data FROM page_links l JOIN pages p ON p.slug=l.page_slug WHERE l.target_slug=? AND p.status='active' ORDER BY p.updated_at DESC,p.slug",
        [slug]), as: WikiPage.self)
  }
  public func referencedPages(source slug: String) throws -> [WikiPage] {
    try decode(
      db.query(
        "SELECT p.data FROM page_sources s JOIN pages p ON p.slug=s.page_slug WHERE s.source_slug=? AND p.status='active' ORDER BY p.updated_at DESC,p.slug",
        [slug]), as: WikiPage.self)
  }
  public func lint() throws -> [[String: String]] {
    let pages = try pages()
    let active = Set(pages.map(\.slug))
    let allSources = try sources()
    var linked = Set<String>()
    var used = Set<String>()
    var findings = [[String: String]]()
    for page in pages {
      used.formUnion(page.sources)
      for id in try materialIDs(in: page) {
        if let slug = try? material(id).sourceSlug { used.insert(slug) }
      }
      for target in Markdown.wikiLinks(page.body) {
        if !active.contains(target) {
          findings.append(["code": "broken_link", "slug": page.slug, "target": target])
        } else if target != page.slug {
          linked.insert(target)
        }
      }
      for id in Markdown.attachmentIDs(page.body) where (try? attachment(id)) == nil {
        findings.append(["code": "missing_attachment", "slug": page.slug, "target": id])
      }
      if page.body.utf8.count > 32 * 1024 {
        findings.append(["code": "large_page", "slug": page.slug])
      }
    }
    for page in pages where !linked.contains(page.slug) {
      findings.append(["code": "orphan_page", "slug": page.slug])
    }
    for source in allSources where !used.contains(source.slug) {
      findings.append(["code": "uncompiled_source", "slug": source.slug])
    }
    return findings
  }
  private func log(_ action: String, slug: String, revision: Int? = nil) throws {
    try db.execute(
      "INSERT INTO log(data) VALUES (?)",
      [
        WikiJSON.encode(
          WikiLog(
            id: UUID().uuidString, action: action, slug: slug, revision: revision,
            at: WikiJSON.now()))
      ])
  }
  public func logs() throws -> [[String: Any]] {
    try db.query("SELECT data FROM log ORDER BY id DESC").map {
      try JSONSerialization.jsonObject(with: Data($0[0].utf8)) as! [String: Any]
    }
  }
  public func saveDraft(_ value: WikiDraft) throws {
    _ = try WikiValidation.slug(value.page.slug)
    guard value.page.body.utf8.count <= 256 * 1024 else { throw WikiError.invalid("draft size") }
    try db.transaction {
      let previous =
        try decode(
          db.query("SELECT data FROM drafts WHERE slug=?", [value.page.slug]), as: WikiDraft.self
        ).first?.page.body ?? (try? page(value.page.slug).body) ?? ""
      try validateNewAttachmentReferences(value.page.body, previous: previous)
      for id in try materialIDs(in: value.page) { _ = try material(id) }
      for citation in value.page.citations { try validateCitation(citation) }
      try db.execute(
        "INSERT INTO drafts VALUES (?,?) ON CONFLICT(slug) DO UPDATE SET data=excluded.data",
        [value.page.slug, WikiJSON.encode(value)])
    }
  }
  public func drafts() throws -> [WikiDraft] {
    try decode(db.query("SELECT data FROM drafts"), as: WikiDraft.self)
  }
  public func deleteDraft(_ slug: String) throws {
    try db.execute("DELETE FROM drafts WHERE slug=?", [slug])
  }
  public func attach(data: Data, name: String) throws -> WikiAttachment {
    guard !data.isEmpty, data.count <= 150 * 1024 * 1024 else {
      throw WikiError.invalid("attachment size (150 MiB)")
    }
    let name = try WikiValidation.text(
      URL(fileURLWithPath: name).lastPathComponent, field: "filename", bytes: 1024, count: 255)
    let value = WikiAttachment(
      id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), name: name,
      byteCount: data.count, sha256: Self.digest(data), createdAt: WikiJSON.now())
    let url = attachmentURL(value)
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    do {
      try db.transaction {
        try db.execute("INSERT INTO attachments VALUES (?,?)", [value.id, WikiJSON.encode(value)])
        try db.registerFileMaterial(value)
        try log("attach", slug: value.id)
      }
    } catch {
      try? FileManager.default.removeItem(at: url)
      throw error
    }
    return value
  }
  public func attachment(_ id: String) throws -> WikiAttachment {
    guard id.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil else {
      throw WikiError.invalid("attachment id")
    }
    guard
      let item = try decode(
        db.query("SELECT data FROM attachments WHERE id=?", [id]), as: WikiAttachment.self
      ).first
    else { throw WikiError.notFound("attachment") }
    return item
  }
  public func attachments() throws -> [WikiAttachment] {
    try decode(db.query("SELECT data FROM attachments"), as: WikiAttachment.self)
  }
  public func attachmentLinkCounts() throws -> [String: Int] {
    // Count each owning document once, including its drafts and preserved revisions.
    // ponytail: scan preserved bodies on file-list refresh; index them if large histories need it.
    let rows = try db.query(
      """
      SELECT 'page:' || page_slug, file_id, '' FROM page_attachments
      UNION ALL SELECT 'page:' || slug, '', json_extract(data,'$.body')
        FROM revisions WHERE instr(data,'attachment')>0
      UNION ALL SELECT 'source:' || slug, '', body
        FROM sources WHERE instr(body,'attachment')>0
      UNION ALL SELECT 'page:' || slug, '', json_extract(data,'$.page.body')
        FROM drafts WHERE instr(data,'attachment')>0
      """)
    var owners = [String: Set<String>]()
    for row in rows {
      for id in row[1].isEmpty ? Markdown.attachmentIDs(row[2]) : [row[1]] {
        owners[id, default: []].insert(row[0])
      }
    }
    return owners.mapValues { $0.count }
  }
  public func renameAttachment(_ id: String, name: String) throws -> WikiAttachment {
    try db.transaction {
      var item = try attachment(id)
      let name = try WikiValidation.text(name, field: "filename", bytes: 1024, count: 255)
      guard !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else {
        throw WikiError.invalid("filename")
      }
      let original = attachmentURL(item)
      item.name = name
      // Stable byte paths make a rename atomic and preserve every historical attachment ID.
      guard attachmentURL(item) == original else {
        throw WikiError.invalid(localized("파일 확장자는 유지해 주세요."))
      }
      try db.execute("UPDATE attachments SET data=? WHERE id=?", [WikiJSON.encode(item), id])
      try log("rename_attachment", slug: id)
      return item
    }
  }
  public func attachmentIsInUse(_ id: String) throws -> Bool {
    for item in try materials(status: "all") where item.fileID == id {
      if try !materialReferences(item.id).isEmpty { return true }
    }
    if !(try db.query("SELECT 1 FROM page_attachments WHERE file_id=? LIMIT 1", [id])).isEmpty {
      return true
    }
    for row in try db.query("SELECT data FROM revisions WHERE instr(data,?)>0", [id]) {
      let page = try WikiJSON.decoder().decode(WikiPage.self, from: Data(row[0].utf8))
      if Markdown.attachmentIDs(page.body).contains(id) { return true }
    }
    for row in try db.query("SELECT body FROM sources WHERE instr(body,?)>0", [id]) {
      if Markdown.attachmentIDs(row[0]).contains(id) { return true }
    }
    for row in try db.query("SELECT data FROM drafts WHERE instr(data,?)>0", [id]) {
      let draft = try WikiJSON.decoder().decode(WikiDraft.self, from: Data(row[0].utf8))
      if Markdown.attachmentIDs(draft.page.body).contains(id) { return true }
    }
    return false
  }
  @discardableResult
  public func trashAttachment(_ id: String) throws -> URL? {
    var original: URL?
    var trashed: NSURL?
    do {
      try db.transaction {
        try Task.checkCancellation()
        let item = try attachment(id)
        guard try !attachmentIsInUse(id) else { throw WikiError.attachmentInUse }
        try Task.checkCancellation()
        let url = attachmentURL(item)
        original = url
        if FileManager.default.fileExists(atPath: url.path) {
          try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        }
        let materialIDs = try db.query(
          "SELECT id FROM materials WHERE json_extract(data,'$.file_id')=?", [id]
        ).map { $0[0] }
        for owner in materialIDs {
          try db.execute("DELETE FROM material_extracts WHERE material_id=?", [owner])
          try db.execute("DELETE FROM materials WHERE id=?", [owner])
        }
        try db.execute("DELETE FROM attachments WHERE id=?", [id])
        try log("trash_attachment", slug: id)
      }
    } catch {
      if let original, let trashed, !FileManager.default.fileExists(atPath: original.path) {
        do { try FileManager.default.moveItem(at: trashed as URL, to: original) } catch {
          throw WikiError.storage(localized("첨부파일 복구에 실패했습니다. 휴지통에서 파일을 복원하세요."))
        }
      }
      throw error
    }
    return trashed as URL?
  }
  private func validateNewAttachmentReferences(_ body: String, previous: String) throws {
    let existing = Set(Markdown.attachmentIDs(previous))
    for id in Markdown.attachmentIDs(body) where !existing.contains(id) {
      _ = try attachment(id)
    }
  }
  public func attachmentURL(_ value: WikiAttachment) -> URL {
    let ext = URL(fileURLWithPath: value.name).pathExtension.lowercased()
    let safe =
      ext.range(of: "^[a-z0-9]{1,10}$", options: .regularExpression) != nil ? "." + ext : ""
    return root.appendingPathComponent("attachments").appendingPathComponent(value.id + safe)
  }
  public func backup(to destination: URL) throws {
    guard !FileManager.default.fileExists(atPath: destination.path) else {
      throw WikiError.invalid("backup destination already exists")
    }
    let stage = destination.deletingLastPathComponent().appendingPathComponent(
      ".Galpium-backup-" + UUID().uuidString)
    try FileManager.default.createDirectory(
      at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    do {
      try Task.checkCancellation()
      try db.backup(to: stage.appendingPathComponent("wiki.sqlite3"))
      let snapshot = try SQLite(
        url: stage.appendingPathComponent("wiki.sqlite3"), readOnly: true)
      let snapshotAttachments = try decode(
        snapshot.query("SELECT data FROM attachments"), as: WikiAttachment.self)
      let dir = stage.appendingPathComponent("attachments")
      try FileManager.default.createDirectory(
        at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      for attachment in snapshotAttachments {
        try Task.checkCancellation()
        let copy = dir.appendingPathComponent(attachmentURL(attachment).lastPathComponent)
        try FileManager.default.copyItem(
          at: attachmentURL(attachment), to: copy)
        guard Self.digest(try Data(contentsOf: copy, options: .mappedIfSafe)) == attachment.sha256
        else { throw WikiError.invalid("backup attachment checksum") }
      }
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: stage.appendingPathComponent("wiki.sqlite3").path)
      let manifest: [String: Any] = [
        "format": "galpium-backup", "version": 1, "created_at": WikiJSON.now(),
        "database_sha256": Self.digest(
          try Data(contentsOf: stage.appendingPathComponent("wiki.sqlite3"), options: .mappedIfSafe)
        ), "attachments": snapshotAttachments.count,
      ]
      try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        .write(to: stage.appendingPathComponent("manifest.json"), options: .atomic)
      try Task.checkCancellation()
      try FileManager.default.moveItem(at: stage, to: destination)
    } catch {
      try? FileManager.default.removeItem(at: stage)
      throw error
    }
  }
  public static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
