import Foundation

extension SQLite {
  func prepareSchema(version: Int, url: URL) throws {
    if version == 3 { return }
    if version == 1 || version == 2 {
      let backupURL = url.deletingLastPathComponent().appendingPathComponent(
        "migration-v\(version)-" + UUID().uuidString + ".sqlite3")
      try backup(to: backupURL)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
    }
    try transaction {
      let current = Int(try query("PRAGMA user_version")[0][0]) ?? 0
      if current == 3 { return }
      guard current == version else {
        throw WikiError.storage("schema changed during migration; reopen the library")
      }
      if version == 1 {
        try executeScript(
          "ALTER TABLE sources RENAME TO legacy_sources; ALTER TABLE pages RENAME TO legacy_pages; ALTER TABLE revisions RENAME TO legacy_revisions;"
        )
      }
      if version < 2 { try executeScript(Self.schema) }
      try executeScript(Self.materialSchema)
      if version == 1 {
        try executeScript("DROP TRIGGER page_writer_insert; DROP TRIGGER page_writer_update;")
        for row in try query("SELECT data FROM legacy_sources") {
          var source = try WikiJSON.decoder().decode(WikiSource.self, from: Data(row[0].utf8))
          let hash = WikiStore.digest(Data(source.body.utf8))
          guard source.sha256 == nil || source.sha256 == hash else {
            throw WikiError.invalid("migration source checksum")
          }
          source.sha256 = hash
          try insertSource(source)
        }
        for row in try query("SELECT data FROM legacy_pages") {
          let page = try WikiJSON.decoder().decode(WikiPage.self, from: Data(row[0].utf8))
          try writePage(page, data: row[0])
        }
        for row in try query(
          "SELECT slug,revision,data FROM legacy_revisions ORDER BY slug,revision")
        {
          let page = try WikiJSON.decoder().decode(WikiPage.self, from: Data(row[2].utf8))
          guard page.slug == row[0], page.revision == Int(row[1]) else {
            throw WikiError.invalid("migration revision identity")
          }
          try execute("INSERT INTO revisions(slug,revision,data) VALUES (?,?,?)", row)
        }
        guard try query("PRAGMA foreign_key_check").isEmpty else {
          throw WikiError.invalid("migration relationships")
        }
        guard
          try query(
            "SELECT p.slug FROM pages p WHERE (SELECT count(*) FROM revisions r WHERE r.slug=p.slug)<>p.revision OR (SELECT min(revision) FROM revisions r WHERE r.slug=p.slug)<>1"
          ).isEmpty
        else { throw WikiError.invalid("migration history sequence") }
        try executeScript(
          "DROP TABLE legacy_revisions; DROP TABLE legacy_pages; DROP TABLE legacy_sources;")
      }
      for row in try query("SELECT data FROM sources") {
        try registerSourceMaterial(
          WikiJSON.decoder().decode(WikiSource.self, from: Data(row[0].utf8)))
      }
      for row in try query("SELECT data FROM attachments") {
        try registerFileMaterial(
          WikiJSON.decoder().decode(WikiAttachment.self, from: Data(row[0].utf8)))
      }
      if version == 1 {
        try executeScript(
          """
          CREATE TRIGGER page_writer_insert BEFORE INSERT ON pages WHEN json_type(new.data,'$.materials') IS NULL BEGIN SELECT RAISE(ABORT,'update Galpium before writing'); END;
          CREATE TRIGGER page_writer_update BEFORE UPDATE ON pages WHEN json_type(new.data,'$.materials') IS NULL BEGIN SELECT RAISE(ABORT,'update Galpium before writing'); END;
          """)
      }
      try executeScript("PRAGMA user_version=3; PRAGMA application_id=0x474c504d;")
    }
  }
  private static let schema = """
    CREATE TABLE sources (
      slug TEXT PRIMARY KEY, title TEXT NOT NULL, body TEXT NOT NULL,
      url TEXT NOT NULL, sha256 TEXT NOT NULL CHECK(length(sha256)=64), created_at TEXT NOT NULL,
      search_text TEXT NOT NULL, data TEXT NOT NULL CHECK(json_valid(data)),
      CHECK(length(CAST(body AS BLOB)) BETWEEN 1 AND 262144),
      CHECK(COALESCE(json_extract(data,'$.slug')=slug,0)),
      CHECK(COALESCE(json_extract(data,'$.body')=body,0)),
      CHECK(COALESCE(json_extract(data,'$.title')=title,0)),
      CHECK(COALESCE(json_extract(data,'$.url')=url,0)),
      CHECK(COALESCE(json_extract(data,'$.sha256')=sha256,0)),
      CHECK(COALESCE(json_extract(data,'$.created_at')=created_at,0))
    ) STRICT;
    CREATE TABLE pages (
      slug TEXT PRIMARY KEY, title TEXT NOT NULL, body TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('active','archived')),
      pinned INTEGER NOT NULL CHECK(pinned IN (0,1)), revision INTEGER NOT NULL CHECK(revision>0),
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, search_text TEXT NOT NULL,
      data TEXT NOT NULL CHECK(json_valid(data)),
      CHECK(length(CAST(body AS BLOB)) BETWEEN 1 AND 65536),
      CHECK(COALESCE(json_extract(data,'$.slug')=slug,0)),
      CHECK(COALESCE(json_extract(data,'$.body')=body,0)),
      CHECK(COALESCE(json_extract(data,'$.title')=title,0)),
      CHECK(COALESCE(json_extract(data,'$.status')=status,0)),
      CHECK(COALESCE(json_extract(data,'$.revision')=revision,0)),
      CHECK(COALESCE(json_extract(data,'$.pinned')=pinned,0)),
      CHECK(COALESCE(json_extract(data,'$.created_at')=created_at,0)),
      CHECK(COALESCE(json_extract(data,'$.updated_at')=updated_at,0)),
      FOREIGN KEY(slug,revision) REFERENCES revisions(slug,revision) DEFERRABLE INITIALLY DEFERRED
    ) STRICT;
    CREATE TABLE revisions (
      slug TEXT NOT NULL REFERENCES pages(slug), revision INTEGER NOT NULL CHECK(revision>0),
      data TEXT NOT NULL CHECK(json_valid(data)), PRIMARY KEY(slug,revision),
      CHECK(COALESCE(json_extract(data,'$.slug')=slug,0)),
      CHECK(COALESCE(json_extract(data,'$.revision')=revision,0))
    ) STRICT;
    CREATE TABLE page_sources (page_slug TEXT NOT NULL REFERENCES pages(slug), source_slug TEXT NOT NULL REFERENCES sources(slug), PRIMARY KEY(page_slug,source_slug)) STRICT;
    CREATE TABLE page_tags (page_slug TEXT NOT NULL REFERENCES pages(slug), tag TEXT NOT NULL CHECK(length(tag) BETWEEN 1 AND 40), PRIMARY KEY(page_slug,tag)) STRICT;
    CREATE TABLE page_links (page_slug TEXT NOT NULL REFERENCES pages(slug), target_slug TEXT NOT NULL, PRIMARY KEY(page_slug,target_slug)) STRICT;
    CREATE TABLE page_attachments (page_slug TEXT NOT NULL REFERENCES pages(slug), file_id TEXT NOT NULL CHECK(length(file_id)=32), PRIMARY KEY(page_slug,file_id)) STRICT;
    CREATE TABLE IF NOT EXISTS attachments (id TEXT PRIMARY KEY, data TEXT NOT NULL CHECK(json_valid(data)));
    CREATE TABLE IF NOT EXISTS log (id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT NOT NULL CHECK(json_valid(data)));
    CREATE TABLE IF NOT EXISTS drafts (slug TEXT PRIMARY KEY, data TEXT NOT NULL CHECK(json_valid(data)));
    CREATE INDEX pages_status_order ON pages(status,pinned DESC,updated_at DESC,slug);
    CREATE INDEX pages_all_order ON pages(pinned DESC,updated_at DESC,slug);
    CREATE INDEX sources_order ON sources(created_at DESC,slug);
    CREATE INDEX source_references ON page_sources(source_slug,page_slug);
    CREATE INDEX tag_pages ON page_tags(tag,page_slug);
    CREATE INDEX incoming_links ON page_links(target_slug,page_slug);
    CREATE INDEX file_references ON page_attachments(file_id,page_slug);
    CREATE VIRTUAL TABLE page_search USING fts5(slug UNINDEXED,search_text,tokenize='trigram case_sensitive 1');
    CREATE VIRTUAL TABLE source_search USING fts5(slug UNINDEXED,search_text,tokenize='trigram case_sensitive 1');
    CREATE TRIGGER source_insert AFTER INSERT ON sources BEGIN INSERT INTO source_search(slug,search_text) VALUES (new.slug,new.search_text); END;
    CREATE TRIGGER page_insert AFTER INSERT ON pages BEGIN INSERT INTO page_search(slug,search_text) VALUES (new.slug,new.search_text); END;
    CREATE TRIGGER page_update AFTER UPDATE ON pages BEGIN DELETE FROM page_search WHERE slug=old.slug; INSERT INTO page_search(slug,search_text) VALUES (new.slug,new.search_text); END;
    CREATE TRIGGER source_immutable_update BEFORE UPDATE ON sources BEGIN SELECT RAISE(ABORT,'immutable source'); END;
    CREATE TRIGGER source_immutable_delete BEFORE DELETE ON sources BEGIN SELECT RAISE(ABORT,'immutable source'); END;
    CREATE TRIGGER revision_immutable_update BEFORE UPDATE ON revisions BEGIN SELECT RAISE(ABORT,'immutable revision'); END;
    CREATE TRIGGER revision_immutable_delete BEFORE DELETE ON revisions BEGIN SELECT RAISE(ABORT,'immutable revision'); END;
    """

  func insertSource(_ source: WikiSource) throws {
    _ = try WikiValidation.slug(source.slug)
    _ = try WikiValidation.text(source.title, field: "title", bytes: 720, count: 180)
    _ = try WikiValidation.text(source.body, field: "body", bytes: 262144, multiline: true)
    _ = try WikiValidation.provenanceURL(source.url)
    let hash = WikiStore.digest(Data(source.body.utf8))
    guard source.sha256 == nil || source.sha256 == hash else {
      throw WikiError.invalid("source checksum")
    }
    var source = source
    source.sha256 = hash
    let search = ([source.slug, source.title, source.body]).joined(separator: "\n")
      .precomposedStringWithCanonicalMapping.lowercased()
    try execute(
      "INSERT INTO sources(slug,title,body,url,sha256,created_at,search_text,data) VALUES (?,?,?,?,?,?,?,?)",
      [
        source.slug, source.title, source.body, source.url, hash, source.createdAt, search,
        WikiJSON.encode(source),
      ])
    try registerSourceMaterial(source)
  }
  func writePage(_ page: WikiPage, data: String? = nil) throws {
    let search = ([page.slug, page.title, page.body] + page.tags).joined(separator: "\n")
      .precomposedStringWithCanonicalMapping.lowercased()
    try execute(
      "INSERT INTO pages(slug,title,body,status,pinned,revision,created_at,updated_at,search_text,data) VALUES (?,?,?,?,?,?,?,?,?,?) ON CONFLICT(slug) DO UPDATE SET title=excluded.title,body=excluded.body,status=excluded.status,pinned=excluded.pinned,revision=excluded.revision,updated_at=excluded.updated_at,search_text=excluded.search_text,data=excluded.data",
      [
        page.slug, page.title, page.body, page.status, page.pinned ? "1" : "0",
        String(page.revision), page.createdAt, page.updatedAt, search,
        try data ?? WikiJSON.encode(page),
      ])
    for table in ["page_sources", "page_tags", "page_links", "page_attachments", "page_materials"] {
      try execute("DELETE FROM \(table) WHERE page_slug=?", [page.slug])
    }
    for source in Set(page.sources) {
      try execute("INSERT INTO page_sources VALUES (?,?)", [page.slug, source])
    }
    for tag in Set(page.tags) {
      try execute("INSERT INTO page_tags VALUES (?,?)", [page.slug, tag])
    }
    for target in Markdown.wikiLinks(page.body) {
      try execute("INSERT INTO page_links VALUES (?,?)", [page.slug, target])
    }
    for id in Markdown.attachmentIDs(page.body) {
      try execute("INSERT INTO page_attachments VALUES (?,?)", [page.slug, id])
    }
    var materialIDs = Set(
      page.materials + page.citations.map(\.materialID) + Markdown.materialIDs(page.body))
    for slug in page.sources + Markdown.sourceIDs(page.body) {
      for row in try query(
        "SELECT id FROM materials WHERE json_extract(data,'$.source_slug')=?", [slug])
      { materialIDs.insert(row[0]) }
    }
    for id in Markdown.attachmentIDs(page.body) { materialIDs.insert(WikiMaterial.fileID(id)) }
    for id in materialIDs where !(try query("SELECT id FROM materials WHERE id=?", [id])).isEmpty {
      try execute("INSERT INTO page_materials VALUES (?,?)", [page.slug, id])
    }

  }
}
