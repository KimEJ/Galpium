import Foundation
import XCTest

@testable import GalpiumCore

final class AttachmentManagementTests: XCTestCase {
  private func makeStore() throws -> WikiStore {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    return try WikiStore(root: root)
  }
  func testLinkCountsDeduplicateOwnersAcrossPagesSourcesDraftsAndHistory() throws {
    let store = try makeStore()
    let linked = try store.attach(data: Data("linked".utf8), name: "linked.txt")
    let unused = try store.attach(data: Data("unused".utf8), name: "unused.txt")
    let link = "[file](attachment:\(linked.id))"
    // A source and page with the same slug remain separate owners.
    let source = try store.ingest(slug: "same", title: "Original", body: link + "\n" + link)
    var page = try store.upsert(
      WikiPage(slug: "same", title: "Page", body: link + "\n" + link, sources: [source.slug]),
      expectedRevision: 0)
    page.body = "link only remains in history"
    page = try store.upsert(page, expectedRevision: 1)
    _ = try store.archive(page.slug, expectedRevision: page.revision)
    try store.saveDraft(WikiDraft(page: WikiPage(slug: page.slug, body: link)))
    try store.saveDraft(WikiDraft(page: WikiPage(slug: "draft-only", body: link + "\n" + link)))
    _ = try store.ingest(
      slug: "code", title: "Code", body: "```\n[file](attachment:\(unused.id))\n```")
    XCTAssertEqual(try store.attachmentLinkCounts()[linked.id], 3)
    XCTAssertNil(try store.attachmentLinkCounts()[unused.id])
    XCTAssertTrue(try store.attachmentIsInUse(linked.id))
    XCTAssertFalse(try store.attachmentIsInUse(unused.id))
    try store.deleteDraft("draft-only")
    XCTAssertEqual(try store.attachmentLinkCounts()[linked.id], 2)
  }
  func testRenamePreservesBytesHistoryAndOlderBackupCompatibility() throws {
    let store = try makeStore()
    let source = try store.ingest(slug: "original", title: "Original", body: "immutable text")
    let bytes = Data("attachment bytes".utf8)
    let file = try store.attach(data: bytes, name: "old.txt")
    let page = try store.upsert(
      WikiPage(
        slug: "page", title: "Page", body: "[old](attachment:\(file.id))", sources: [source.slug]),
      expectedRevision: 0)
    let backup = store.root.appendingPathComponent("before-rename")
    try store.backup(to: backup)
    let renamed = try store.renameAttachment(file.id, name: "새 이름.txt")
    XCTAssertEqual(renamed.id, file.id)
    XCTAssertEqual(renamed.sha256, file.sha256)
    XCTAssertEqual(store.attachmentURL(renamed), store.attachmentURL(file))
    XCTAssertEqual(try Data(contentsOf: store.attachmentURL(renamed)), bytes)
    XCTAssertEqual(try store.history(page.slug), [page])
    _ = try store.importBackup(from: backup)
    XCTAssertEqual(try store.attachment(file.id).name, "새 이름.txt")
    XCTAssertThrowsError(try store.renameAttachment(file.id, name: "../escape.txt"))
    XCTAssertThrowsError(try store.renameAttachment(file.id, name: "changed.pdf"))
    XCTAssertEqual(try store.attachment(file.id).name, "새 이름.txt")
  }
  func testHistoryOriginalsAndDraftReferencesPreventDeletion() throws {
    let store = try makeStore()
    let source = try store.ingest(slug: "original", title: "Original", body: "text")
    let history = try store.attach(data: Data("past".utf8), name: "past.txt")
    var page = try store.upsert(
      WikiPage(
        slug: "page", title: "Page", body: "[past](attachment:\(history.id))",
        sources: [source.slug]),
      expectedRevision: 0)
    page.body = "removed from current body"
    page = try store.upsert(page, expectedRevision: 1)
    _ = try store.archive(page.slug, expectedRevision: page.revision)
    let original = try store.attach(data: Data("source".utf8), name: "source.txt")
    _ = try store.ingest(
      slug: "file-source", title: "File source", body: "[source](attachment:\(original.id))")
    let draft = try store.attach(data: Data("draft".utf8), name: "draft.txt")
    try store.saveDraft(
      WikiDraft(page: WikiPage(slug: "draft", body: "[draft](attachment:\(draft.id))")))
    for item in [history, original, draft] {
      XCTAssertTrue(try store.attachmentIsInUse(item.id))
      XCTAssertThrowsError(try store.trashAttachment(item.id)) { error in
        XCTAssertEqual(error as? WikiError, .attachmentInUse)
      }
      XCTAssertTrue(FileManager.default.fileExists(atPath: store.attachmentURL(item).path))
    }
    XCTAssertEqual(try store.history(page.slug).count, 3)
  }
  func testUnusedDeletionUsesTrashAndDatabaseFailureRestoresBytes() throws {
    let store = try makeStore()
    let bytes = Data("recoverable bytes".utf8)
    let item = try store.attach(data: bytes, name: "unused.txt")
    let original = store.attachmentURL(item)
    let trashed = try XCTUnwrap(store.trashAttachment(item.id))
    defer {
      if FileManager.default.fileExists(atPath: trashed.path) {
        try? FileManager.default.moveItem(at: trashed, to: original)
      }
    }
    XCTAssertEqual(try Data(contentsOf: trashed), bytes)
    XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
    XCTAssertThrowsError(try store.attachment(item.id))
    let retained = try store.attach(data: bytes, name: "rollback.txt")
    try store.db.executeScript(
      "CREATE TRIGGER block_file_delete BEFORE DELETE ON attachments BEGIN SELECT RAISE(ABORT,'simulated metadata failure'); END;"
    )
    XCTAssertThrowsError(try store.trashAttachment(retained.id))
    XCTAssertEqual(try store.attachment(retained.id), retained)
    XCTAssertEqual(try Data(contentsOf: store.attachmentURL(retained)), bytes)
  }
  func testStaleWriterCannotAddDeletedAttachmentToPagePatchOrDraft() throws {
    let store = try makeStore()
    let source = try store.ingest(slug: "original", title: "Original", body: "text")
    let item = try store.attach(data: Data("unused".utf8), name: "unused.txt")
    let other = try WikiStore(root: store.root)
    let page = try other.upsert(
      WikiPage(slug: "page", title: "Page", body: "body", sources: [source.slug]),
      expectedRevision: 0)
    let original = store.attachmentURL(item)
    let trashed = try XCTUnwrap(store.trashAttachment(item.id))
    defer {
      if FileManager.default.fileExists(atPath: trashed.path) {
        try? FileManager.default.moveItem(at: trashed, to: original)
      }
    }
    let link = "[deleted](attachment:\(item.id))"
    XCTAssertThrowsError(
      try other.upsert(
        WikiPage(slug: "late", title: "Late", body: link, sources: [source.slug]),
        expectedRevision: 0))
    XCTAssertThrowsError(
      try other.patch(
        page.slug, expectedRevision: 1, replacements: [TextReplacement("body", link)]))
    XCTAssertThrowsError(try other.saveDraft(WikiDraft(page: WikiPage(slug: "draft", body: link))))
    XCTAssertEqual(try other.page(page.slug).revision, 1)
    XCTAssertEqual(try other.drafts().count, 0)
  }
}
