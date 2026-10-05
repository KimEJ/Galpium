import Foundation

private struct BackupPage {
  var slug: String
  var revisions: [WikiPage]
}
extension WikiStore {
  private func mergeBackup(sources: [WikiSource], pages: [BackupPage], logs: [[String: Any]]) throws
    -> (
      sources: Int, pages: Int
    )
  {
    var sourceCount = 0
    var pageCount = 0
    for var item in sources {
      try Task.checkCancellation()
      item.slug = try WikiValidation.slug(item.slug)
      _ = try WikiValidation.text(item.title, field: "title", bytes: 720, count: 180)
      _ = try WikiValidation.text(item.body, field: "body", bytes: 256 * 1024, multiline: true)
      _ = try WikiValidation.provenanceURL(item.url)
      let hash = Self.digest(Data(item.body.utf8))
      guard item.sha256 == nil || item.sha256 == hash else {
        throw WikiError.invalid("source checksum")
      }
      item.sha256 = hash
      if let row = try db.query("SELECT data FROM sources WHERE slug=?", [item.slug]).first {
        let existing = try WikiJSON.decoder().decode(WikiSource.self, from: Data(row[0].utf8))
        guard existing == item else { throw WikiError.immutable }
      } else {
        try db.insertSource(item)
        sourceCount += 1
      }
    }
    for item in pages {
      try Task.checkCancellation()
      _ = try WikiValidation.slug(item.slug)
      guard !item.revisions.isEmpty else { throw WikiError.invalid("empty history") }
      var previous = 0
      for value in item.revisions {
        guard value.slug == item.slug, value.revision == previous + 1,
          ["active", "archived"].contains(value.status)
        else { throw WikiError.invalid("revision sequence") }
        _ = try validate(value)
        previous = value.revision
      }
      if let row = try db.query("SELECT data FROM pages WHERE slug=?", [item.slug]).first {
        let existing = try WikiJSON.decoder().decode(WikiPage.self, from: Data(row[0].utf8))
        guard existing == item.revisions.last,
          try history(item.slug).reversed().map({ $0 }) == item.revisions
        else { throw WikiError.immutable }
      } else {
        try db.writePage(item.revisions.last!)
        for value in item.revisions {
          try db.execute(
            "INSERT INTO revisions(slug,revision,data) VALUES (?,?,?)",
            [value.slug, String(value.revision), WikiJSON.encode(value)])
        }
        pageCount += 1
      }
    }
    if sourceCount > 0 || pageCount > 0 {
      for row in logs {
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        try db.execute(
          "INSERT INTO log(data) VALUES (?)", [String(decoding: data, as: UTF8.self)])
      }
    }
    return (sourceCount, pageCount)
  }
  public func importBackup(from directory: URL) throws -> (sources: Int, pages: Int) {
    let manifestURL = directory.appendingPathComponent("manifest.json")
    if FileManager.default.fileExists(atPath: manifestURL.path) {
      guard
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
          as? [String: Any], manifest["format"] as? String == "galpium-backup",
        manifest["version"] as? Int == 1,
        manifest["database_sha256"] as? String
          == Self.digest(
            try Data(
              contentsOf: directory.appendingPathComponent("wiki.sqlite3"), options: .mappedIfSafe))
      else { throw WikiError.invalid("backup database checksum / version") }
    }
    let snapshot = try SQLite(url: directory.appendingPathComponent("wiki.sqlite3"), readOnly: true)
    func decode<T: Decodable>(_ table: String, as type: T.Type) throws -> [T] {
      try snapshot.query("SELECT data FROM \(table)").map {
        try WikiJSON.decoder().decode(type, from: Data($0[0].utf8))
      }
    }
    let sources = try decode("sources", as: WikiSource.self)
    let revisions = try decode("revisions", as: WikiPage.self)
    let attachments = try decode("attachments", as: WikiAttachment.self)
    let schemaVersion = Int(try snapshot.query("PRAGMA user_version")[0][0]) ?? 0
    let incomingMaterials = schemaVersion >= 3 ? try decode("materials", as: WikiMaterial.self) : []
    let incomingExtractions =
      schemaVersion >= 3 ? try decode("material_extracts", as: MaterialExtraction.self) : []
    let grouped = Dictionary(grouping: revisions, by: \.slug).map {
      BackupPage(slug: $0.key, revisions: $0.value.sorted { $0.revision < $1.revision })
    }
    let log = try snapshot.query("SELECT data FROM log ORDER BY id").map {
      try JSONSerialization.jsonObject(with: Data($0[0].utf8)) as! [String: Any]
    }
    let drafts = try decode("drafts", as: WikiDraft.self)
    // Verify all bytes before writing any metadata. Attachment IDs cannot choose filesystem paths.
    for item in attachments {
      try Task.checkCancellation()
      guard item.id.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil,
        item.byteCount > 0, item.byteCount <= 150 * 1024 * 1024
      else { throw WikiError.invalid("backup attachment") }
      let origin = directory.appendingPathComponent("attachments").appendingPathComponent(
        attachmentURL(item).lastPathComponent)
      let info = try origin.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
      guard info.isSymbolicLink != true, info.fileSize == item.byteCount else {
        throw WikiError.invalid("backup file")
      }
      guard Self.digest(try Data(contentsOf: origin, options: .mappedIfSafe)) == item.sha256 else {
        throw WikiError.invalid("backup checksum")
      }
      if let existing = try? attachment(item.id) {
        guard existing.sha256 == item.sha256, existing.byteCount == item.byteCount,
          attachmentURL(existing) == attachmentURL(item)
        else { throw WikiError.immutable }
      }
    }
    let existingMaterialIDs = Set(try materials(status: "all").map(\.id))
    return try db.transaction {
      for item in attachments {
        try Task.checkCancellation()
        let origin = directory.appendingPathComponent("attachments").appendingPathComponent(
          attachmentURL(item).lastPathComponent)
        let target = attachmentURL(item)
        if !FileManager.default.fileExists(atPath: target.path) {
          try FileManager.default.copyItem(at: origin, to: target)
          try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: target.path)
        }
        guard Self.digest(try Data(contentsOf: target, options: .mappedIfSafe)) == item.sha256
        else {
          throw WikiError.invalid("existing attachment checksum")
        }
        try db.execute(
          "INSERT INTO attachments VALUES (?,?) ON CONFLICT(id) DO NOTHING",
          [item.id, WikiJSON.encode(item)])
      }
      for item in attachments { try db.registerFileMaterial(item) }
      let originalResult = try mergeBackup(sources: sources, pages: [], logs: [])
      for item in incomingMaterials {
        _ = try WikiValidation.slug(item.id)
        _ = try WikiValidation.text(item.title, field: "material title", bytes: 1024, count: 255)
        _ = try WikiValidation.provenanceURL(item.url)
        guard (item.sourceSlug != nil) != (item.fileID != nil) else {
          throw WikiError.invalid("material payload")
        }
        guard item.revision > 0, ["active", "archived"].contains(item.status),
          ["text", "pdf", "image", "file"].contains(item.kind)
        else { throw WikiError.invalid("backup material") }
        if let slug = item.sourceSlug {
          guard try self.source(slug).sha256 == item.originalHash else {
            throw WikiError.invalid("material checksum")
          }
        }
        if let id = item.fileID {
          guard try attachment(id).sha256 == item.originalHash else {
            throw WikiError.invalid("material checksum")
          }
        }
        if let existing = try? material(item.id) {
          guard
            existing.originalHash == item.originalHash && existing.fileID == item.fileID
              && existing.sourceSlug == item.sourceSlug
          else { throw WikiError.immutable }
        } else {
          try db.registerMaterial(item)
        }
        if !existingMaterialIDs.contains(item.id) {
          try db.execute(
            "UPDATE materials SET data=? WHERE id=?", [WikiJSON.encode(item), item.id])
        }
      }
      for text in incomingExtractions {
        let owner = try material(text.materialID)
        guard owner.originalHash == text.originalHash,
          Self.digest(try WikiJSON.encoder().encode(text.pages)) == text.textHash,
          text.id
            == Self.digest(
              Data((text.materialID + text.originalHash + text.method + text.textHash).utf8))
        else { throw WikiError.invalid("backup extraction") }
        if let existing = try? extraction(text.id) {
          guard existing == text else { throw WikiError.immutable }
        } else {
          try db.execute(
            "INSERT INTO material_extracts VALUES (?,?,?)",
            [text.id, text.materialID, WikiJSON.encode(text)])
        }
      }
      let result = try mergeBackup(sources: [], pages: grouped, logs: log)
      for draft in drafts
      where try db.query("SELECT data FROM drafts WHERE slug=?", [draft.page.slug]).isEmpty {
        try saveDraft(draft)
      }
      if originalResult.sources > 0 && result.pages == 0 {
        for row in log {
          try db.execute(
            "INSERT INTO log(data) VALUES (?)",
            [
              String(
                decoding: try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
                as: UTF8.self)
            ])
        }
      }
      return (sources: originalResult.sources, pages: result.pages)
    }
  }
}
