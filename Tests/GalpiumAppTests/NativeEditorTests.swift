import AppKit
import GalpiumCore
import XCTest

@testable import GalpiumApp

final class NativeEditorTests: XCTestCase {
  func testSidebarNavigationHasOneDestinationAndClearsStaleSource() async throws {
    await MainActor.run {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      model.status = "archived"
      model.section = "home"
      XCTAssertEqual(model.sidebarDestination, .archive)
      model.home()
      XCTAssertEqual(model.sidebarDestination, .wiki)
      XCTAssertEqual(model.status, "active")
      model.status = "archived"
      model.showSources()
      XCTAssertEqual(model.sidebarDestination, .materials)
      model.selectedSource = "previous-source"
      model.showArchive()
      XCTAssertEqual(model.sidebarDestination, .archive)
      XCTAssertEqual(model.status, "archived")
      XCTAssertNil(model.selectedSource)
      model.showArchive()
      XCTAssertEqual(model.sidebarDestination, .archive)
      model.home()
      XCTAssertEqual(model.sidebarDestination, .wiki)
      XCTAssertEqual(model.status, "active")
    }
  }
  func testDoneWaitsForAttachmentWorkEvenWithoutTextChanges() async throws {
    await MainActor.run {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      model.newPage()
      model.draft.title = "문서"
      model.draft.body = "본문"
      XCTAssertTrue(model.save())
      XCTAssertFalse(model.dirty)
      model.isBusy = true
      model.operationName = "파일 첨부"
      model.finish()
      XCTAssertTrue(model.isEditing)
      model.isBusy = false
      model.finish()
      XCTAssertFalse(model.isEditing)
    }
  }
  func testSourcePickerFindsOlderSourcesAndKeepsSelectedSourcesVisible() async throws {
    try await MainActor.run {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      let store = try XCTUnwrap(model.store)
      for i in 0..<125 {
        _ = try store.ingest(
          slug: "source-\(i)", title: String(format: "원본%03d번", i), body: "자료 \(i)")
      }
      model.newPage()
      XCTAssertEqual(model.pickerSources.count, 100)
      XCTAssertEqual(model.pickerTotal, 125)
      model.morePickerSources()
      XCTAssertEqual(model.pickerSources.count, 125)
      model.pickerQuery = "원본000번"
      model.pickerQueryChanged()
      XCTAssertEqual(model.pickerSources.map(\.slug), ["source-0"])
      model.draft.sources = ["source-0"]
      model.sourceSelectionChanged()
      model.pickerQuery = "없는 검색어"
      model.pickerQueryChanged()
      XCTAssertTrue(model.pickerSources.isEmpty)
      XCTAssertEqual(model.selectedPickerSources.map(\.slug), ["source-0"])
      XCTAssertEqual(model.citationTitles["source-0"], "원본000번")
      model.draft.sources = []
      model.sourceSelectionChanged()
      XCTAssertTrue(model.selectedPickerSources.isEmpty)
    }
  }
  func testKoreanMarkedTextCannotCommitUntilCompositionEnds() async throws {
    try await MainActor.run {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "galpium-ime-" + UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
      model.newPage()
      model.draft.title = "한글 입력 시험"
      model.editor.textView = view
      view.setMarkedText(
        "ㅎ", selectedRange: NSRange(location: 1, length: 0),
        replacementRange: NSRange(location: NSNotFound, length: 0))
      view.setMarkedText(
        "한", selectedRange: NSRange(location: 1, length: 0),
        replacementRange: NSRange(location: NSNotFound, length: 0))
      model.draft.body = view.string
      XCTAssertTrue(view.hasMarkedText())
      XCTAssertFalse(model.save())
      XCTAssertEqual(try model.store?.pages().count, 0)
      view.unmarkText()
      XCTAssertFalse(view.hasMarkedText())
      model.draft.body = view.string
      XCTAssertTrue(model.save())
      XCTAssertEqual(try model.store?.pages().first?.body, "한")
    }
  }
  func testUTF16FormattingUndoAndSelectedText() async throws {
    await MainActor.run {
      let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
      let window = NSWindow(
        contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = view
      window.makeFirstResponder(view)
      view.isRichText = false
      view.allowsUndo = true
      view.string = "앞 😀 한글 뒤"
      let range = (view.string as NSString).range(of: "😀 한글")
      XCTAssertNotNil(view.undoManager)
      view.undoManager?.beginUndoGrouping()
      view.setSelectedRange(range)
      view.format("bold")
      view.undoManager?.endUndoGrouping()
      XCTAssertEqual(view.string, "앞 **😀 한글** 뒤")
      XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "😀 한글")
      view.undoManager?.undo()
      XCTAssertEqual(view.string, "앞 😀 한글 뒤")
      window.close()
    }
  }
  func testDraftTagFieldKeepsTrailingCommaAndRecoveryBase() async throws {
    try await MainActor.run {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "galpium-draft-" + UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      model.newPage()
      model.draft.title = "메모"
      model.draft.body = "첫 본문"
      model.draftTags = "운영,"
      model.tagsChanged()
      XCTAssertEqual(model.draftTags, "운영,")
      model.draftTags += " 배포"
      model.tagsChanged()
      XCTAssertEqual(model.draft.tags, ["운영", "배포"])
      XCTAssertTrue(model.save())
      model.draft.body = "기기 초안"
      XCTAssertTrue(model.flushDraft())
      let draft = try XCTUnwrap(model.store?.drafts().first)
      XCTAssertEqual(draft.page.revision, 1)
    }
  }
  func testReturningToSavedContentRemovesStaleRecoveryDraft() async throws {
    try await MainActor.run {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      model.newPage()
      model.draft.title = "문서"
      model.draft.body = "저장된 본문"
      XCTAssertTrue(model.save())
      model.draft.body = "미저장 변경"
      XCTAssertTrue(model.flushDraft())
      XCTAssertEqual(try model.store?.drafts().count, 1)
      model.draft.body = "저장된 본문"
      model.changed()
      XCTAssertFalse(model.dirty)
      XCTAssertEqual(try model.store?.drafts().count, 0)
    }
  }
}
