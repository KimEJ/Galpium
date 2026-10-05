import Foundation
import XCTest

@testable import GalpiumCore

final class WikiStoreTests: XCTestCase {
  private var root: URL!
  private var store: WikiStore!
  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "galpium-test-" + UUID().uuidString)
    store = try WikiStore(root: root)
  }
  override func tearDownWithError() throws {
    store = nil
    try FileManager.default.removeItem(at: root)
  }
  private func original(_ slug: String = "원본") throws -> WikiSource {
    try store.ingest(
      slug: slug, title: "운영 메모", body: "배포 후 상태를 확인합니다.", url: "https://example.com/source")
  }
  private func document(_ slug: String = "운영") throws -> WikiPage {
    _ = try original()
    return try store.upsert(
      WikiPage(
        slug: slug, title: "운영 절차", body: "## 배포\n배포 후 상태를 확인합니다. [원본](source:원본)", sources: ["원본"],
        tags: ["운영"]), expectedRevision: 0)
  }
  func testOriginalsAreImmutableAndPersistExactly() throws {
    let original = try original()
    XCTAssertEqual(try self.original(), original)
    XCTAssertThrowsError(try store.ingest(slug: "원본", title: original.title, body: "다른 내용"))
    let document = try document()
    let reopened = try WikiStore(root: root)
    XCTAssertEqual(try reopened.source("원본"), original)
    XCTAssertEqual(try reopened.page(document.slug), document)
    XCTAssertEqual(original.sha256, WikiStore.digest(Data(original.body.utf8)))
  }
  func testTwoIndependentWritersRejectStaleUpdateAndRetainHistory() throws {
    var page = try document()
    let second = try WikiStore(root: root)
    var competing = page
    competing.body = "다른 프로세스"
    page.body = "첫 프로세스"
    _ = try store.upsert(page, expectedRevision: 1)
    XCTAssertThrowsError(try second.upsert(competing, expectedRevision: 1)) {
      XCTAssertEqual($0 as? WikiError, .conflict(2))
    }
    XCTAssertEqual(try second.page(page.slug).body, "첫 프로세스")
    XCTAssertEqual(try second.history(page.slug).count, 2)
    XCTAssertEqual(
      try second.page(page.slug, revision: 1).body, "## 배포\n배포 후 상태를 확인합니다. [원본](source:원본)")
  }
  func testSimultaneousWritersCommitOnlyOneRevision() throws {
    let page = try document()
    let first = try XCTUnwrap(store)
    let second = try WikiStore(root: root)
    let counter = ConcurrentResults()
    DispatchQueue.concurrentPerform(iterations: 2) { i in
      var value = page
      value.body = "동시 변경 \(i)"
      do {
        _ = try (i == 0 ? first : second).upsert(value, expectedRevision: 1)
        counter.increment(success: true)
      } catch WikiError.conflict { counter.increment(success: false) } catch {
        XCTFail("Unexpected failure: \(error)")
      }
    }
    XCTAssertEqual(counter.successes, 1)
    XCTAssertEqual(counter.conflicts, 1)
    XCTAssertEqual(try store.history(page.slug).count, 2)
  }
  func testArchiveRestoreAndLostResponseRetry() throws {
    var page = try document()
    page.body = "수정 본문"
    page.pinned = true
    let edited = try store.upsert(page, expectedRevision: 1)
    XCTAssertEqual(try store.upsert(page, expectedRevision: 1), edited)
    _ = try store.archive(page.slug, expectedRevision: 2)
    XCTAssertTrue(try store.pages().isEmpty)
    XCTAssertThrowsError(try store.restore(page.slug, revision: 1, expectedRevision: 2))
    let restored = try store.restore(page.slug, revision: 1, expectedRevision: 3)
    XCTAssertEqual(restored.revision, 4)
    XCTAssertEqual(restored.status, "active")
    XCTAssertFalse(restored.pinned)
    XCTAssertEqual(try store.restore(page.slug, revision: 1, expectedRevision: 3), restored)
    XCTAssertEqual(try store.history(page.slug).count, 4)
  }
  func testPatchIsAtomicUniqueOverlapGuardedAndRetryable() throws {
    var page = try document()
    page.body = "가나다 abc 123"
    _ = try store.upsert(page, expectedRevision: 1)
    XCTAssertThrowsError(
      try store.patch(
        page.slug, expectedRevision: 2,
        replacements: [TextReplacement("가나다", "x"), TextReplacement("나다", "y")]))
    XCTAssertEqual(try store.page(page.slug).body, page.body)
    let changed = try store.patch(
      page.slug, expectedRevision: 2,
      replacements: [TextReplacement("abc", "def"), TextReplacement("123", "456")], note: "두 곳 수정")
    XCTAssertEqual(changed.body, "가나다 def 456")
    XCTAssertEqual(
      try store.patch(
        page.slug, expectedRevision: 2,
        replacements: [TextReplacement("abc", "def"), TextReplacement("123", "456")], note: "두 곳 수정"
      ), changed)
    XCTAssertThrowsError(try TextTools.replace("aaaa", replacements: [TextReplacement("aa", "b")]))
  }
  func testNormalizedAllTermSearchAndExactTagPinFilters() throws {
    var page = try document()
    page.slug = "둘째"
    page.pinned = true
    page.tags = ["운영 지원"]
    _ = try store.upsert(page, expectedRevision: 0)
    XCTAssertEqual(try store.pages().first?.slug, "둘째")
    XCTAssertEqual(try store.pages(tag: "운영").count, 1)
    XCTAssertTrue(try store.pages(tag: "운영%").isEmpty)
    XCTAssertEqual(try store.pages(query: "배포 확인".decomposedStringWithCanonicalMapping).count, 2)
    XCTAssertTrue(try store.pages(query: "배포 없는단어").isEmpty)
    XCTAssertEqual(try store.sources(query: "확인").count, 1)
  }
  func testDirectWritingPreservesOriginalAndInvalidSaveRollsBackOriginal() throws {
    let value = try store.upsert(
      WikiPage(slug: "메모", title: "직접 작성", body: "내 메모"), expectedRevision: 0,
      preserveOriginal: true)
    XCTAssertEqual(value.sources.count, 1)
    XCTAssertEqual(try store.source(value.sources[0]).body, value.body)
    XCTAssertThrowsError(
      try store.upsert(
        WikiPage(slug: "../escape", title: "새 글", body: "새 원본"), expectedRevision: 0,
        preserveOriginal: true))
    XCTAssertEqual(try store.sources().count, 1)
  }
  func testDraftRecoveryKeepsItsBaseRevision() throws {
    var page = try document()
    page.body = "저장하지 않은 기기 초안"
    try store.saveDraft(WikiDraft(page: page))
    let reopened = try WikiStore(root: root)
    let draft = try XCTUnwrap(reopened.drafts().first)
    XCTAssertEqual(draft.page.revision, 1)
    XCTAssertEqual(draft.page.body, "저장하지 않은 기기 초안")
    XCTAssertNotEqual(draft.page.body, try reopened.page(page.slug).body)
    try reopened.deleteDraft(page.slug)
    XCTAssertTrue(try store.drafts().isEmpty)
  }
  func testValidationRejectsPathsTypesMissingSourcesAndOversizeText() throws {
    for slug in ["../escape", "/tmp/data", "a/b", "__proto__", "a\u{0}b"] {
      XCTAssertThrowsError(try store.ingest(slug: slug, title: "자료", body: "내용"))
    }
    for url in ["file:///etc/passwd", "javascript:alert(1)", "https://user:password@example.com/"] {
      XCTAssertThrowsError(try store.ingest(slug: "자료", title: "자료", body: "내용", url: url))
    }
    _ = try original()
    XCTAssertThrowsError(
      try store.upsert(WikiPage(slug: "문서", title: "제목", body: "내용"), expectedRevision: 0))
    XCTAssertThrowsError(
      try store.upsert(
        WikiPage(
          slug: "문서", title: "제목", body: String(repeating: "한", count: 22000), sources: ["원본"]),
        expectedRevision: 0))
    XCTAssertThrowsError(try store.attach(data: Data(), name: "empty"))
  }
  func testBackupRoundTripPreservesSourcesHistoryAndDivergentImportIsAtomic() throws {
    var page = try document()
    page.body += "\n두 번째 개정"
    _ = try store.upsert(page, expectedRevision: 1)
    let backup = root.appendingPathComponent("roundtrip-backup")
    try store.backup(to: backup)
    let destinationRoot = root.appendingPathComponent("imported")
    let destination = try WikiStore(root: destinationRoot)
    let result = try destination.importBackup(from: backup)
    XCTAssertEqual(result.sources, 1)
    XCTAssertEqual(result.pages, 1)
    XCTAssertEqual(try destination.source("원본"), try store.source("원본"))
    XCTAssertEqual(try destination.history("운영"), try store.history("운영"))
    XCTAssertEqual(try destination.importBackup(from: backup).pages, 0)
    let incoming = try WikiStore(root: root.appendingPathComponent("divergent-library"))
    _ = try incoming.ingest(slug: "new-before-conflict", title: "새 원본", body: "원자성")
    var changed = try store.source("원본")
    changed.body = "잘못된 기존 원본"
    changed.sha256 = WikiStore.digest(Data(changed.body.utf8))
    try incoming.db.insertSource(changed)
    let divergent = root.appendingPathComponent("divergent-backup")
    try incoming.backup(to: divergent)
    XCTAssertThrowsError(try destination.importBackup(from: divergent))
    XCTAssertEqual(try destination.sources().count, 1)
  }
  func testFullBackupRestoresAttachmentBytesAndHistory() throws {
    let attachment = try store.attach(data: Data("첨부 원본 bytes".utf8), name: "proof.txt")
    var page = try document()
    page.body += "\n[파일](attachment:\(attachment.id))"
    _ = try store.upsert(page, expectedRevision: 1)
    var draft = page
    draft.revision = 2
    draft.body = "아직 저장하지 않은 복구 초안"
    try store.saveDraft(WikiDraft(page: draft))
    let backup = root.appendingPathComponent("backup")
    try store.backup(to: backup)
    let destination = try WikiStore(root: root.appendingPathComponent("restored"))
    let result = try destination.importBackup(from: backup)
    XCTAssertEqual(result.pages, 1)
    XCTAssertEqual(try destination.history(page.slug), try store.history(page.slug))
    XCTAssertEqual(
      try Data(contentsOf: destination.attachmentURL(attachment)), Data("첨부 원본 bytes".utf8))
    XCTAssertEqual(try destination.attachment(attachment.id).sha256, attachment.sha256)
    XCTAssertEqual(try destination.logs().count, try store.logs().count)
    XCTAssertEqual(try destination.drafts().first?.page.body, draft.body)
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: backup.appendingPathComponent("wiki.sqlite3-wal").path)
    )
    try Data("corrupt".utf8).write(
      to: backup.appendingPathComponent("attachments").appendingPathComponent(
        store.attachmentURL(attachment).lastPathComponent))
    let another = try WikiStore(root: root.appendingPathComponent("rejected"))
    XCTAssertThrowsError(try another.importBackup(from: backup))
    XCTAssertTrue(try another.pages().isEmpty)
  }
  func testBackupImportRejectsCorruptExistingFileAndRollsBackText() throws {
    _ = try document()
    let attachment = try store.attach(data: Data("valid bytes".utf8), name: "proof.txt")
    let backup = root.appendingPathComponent("backup")
    try store.backup(to: backup)
    let target = try WikiStore(root: root.appendingPathComponent("target"))
    try Data("do not overwrite".utf8).write(to: target.attachmentURL(attachment))
    XCTAssertThrowsError(try target.importBackup(from: backup))
    XCTAssertTrue(try target.pages().isEmpty)
    XCTAssertTrue(try target.sources().isEmpty)
    XCTAssertEqual(
      try Data(contentsOf: target.attachmentURL(attachment)), Data("do not overwrite".utf8))
  }
  func testFutureDatabaseVersionIsNeverDowngraded() throws {
    try store.db.execute("PRAGMA user_version=99")
    XCTAssertThrowsError(try WikiStore(root: root))
    XCTAssertEqual(try store.db.query("PRAGMA user_version")[0][0], "99")
  }
  func testBackupManifestRejectsDatabaseCorruptionBeforeImport() throws {
    _ = try document()
    let backup = root.appendingPathComponent("backup")
    try store.backup(to: backup)
    let handle = try FileHandle(forWritingTo: backup.appendingPathComponent("wiki.sqlite3"))
    try handle.seek(toOffset: 120)
    try handle.write(contentsOf: Data([0x42]))
    try handle.close()
    let target = try WikiStore(root: root.appendingPathComponent("target"))
    XCTAssertThrowsError(try target.importBackup(from: backup))
    XCTAssertTrue(try target.pages().isEmpty)
  }
  func testUniqueWhitespacePatchIsAccepted() throws {
    XCTAssertEqual(
      try TextTools.replace("a\nb", replacements: [TextReplacement("\n", "\n\n")]), "a\n\nb")
  }
  func testMarkdownTableLinksUnsafeSchemesAndCodeExclusion() throws {
    XCTAssertEqual(Markdown.cells("| [[문서|표시]] | `a|b` | x\\|y |"), ["[[문서|표시]]", "`a|b`", "x|y"])
    XCTAssertEqual(
      Markdown.wikiLinks(
        "[[진짜]] `[[코드]]`\n```\n[[예시]]\n```\n| 링크 | 설명 |\n| --- | --- |\n| [[표문서|표시]] | 내용 |"),
      ["진짜", "표문서"])
    XCTAssertNil(Markdown.safeLink("javascript:alert(1)"))
    XCTAssertNil(Markdown.safeLink("file:///etc/passwd"))
    XCTAssertNil(Markdown.safeLink("https://user:secret@example.com"))
    XCTAssertTrue(Markdown.blocks("<script>alert(1)</script>")[0].text.contains("<script>"))
    let id = String(repeating: "a", count: 32)
    XCTAssertEqual(Markdown.attachmentIDs("![사진](attachment:\(id)) `![예](attachment:\(id))`"), [id])
  }
  func testDiffLineNumbersAndBoundedFallback() throws {
    let diff = TextTools.diff("one\ntwo\nthree", "one\n둘\nthree")
    XCTAssertEqual(diff.added, 1)
    XCTAssertEqual(diff.removed, 1)
    XCTAssertEqual(diff.rows.first { $0.type == "add" }?.newLine, 2)
    XCTAssertEqual(diff.rows.first { $0.type == "remove" }?.oldLine, 2)
    XCTAssertTrue(
      TextTools.diff(
        Array(repeating: "a", count: 600).joined(separator: "\n"),
        Array(repeating: "b", count: 600).joined(separator: "\n")
      ).coarse)
    XCTAssertTrue(TextTools.diff("same", "same").rows.isEmpty)
  }
}

private final class ConcurrentResults: @unchecked Sendable {
  private let lock = NSLock()
  private var values = [0, 0]
  var successes: Int {
    lock.lock()
    defer { lock.unlock() }
    return values[0]
  }
  var conflicts: Int {
    lock.lock()
    defer { lock.unlock() }
    return values[1]
  }
  func increment(success: Bool) {
    lock.lock()
    defer { lock.unlock() }
    values[success ? 0 : 1] += 1
  }
}
