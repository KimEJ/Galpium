import AppKit
import GalpiumCore
import SwiftUI
import XCTest

@testable import GalpiumApp

final class MaterialsUITests: XCTestCase {
  func testChatProvenanceReaderAtMinimumStandardAndDarkSizes() async throws {
    try await MainActor.run {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      let store = try XCTUnwrap(model.store)
      let link = "codex://threads/01900000-0000-7000-8000-000000000001"
      let prompt = """
        요청 프롬프트: 자료를 바탕으로 기존 위키를 갱신하고, 필요한 부분을 글과 도표로 설명해줘.

        채팅 링크: \(link)

        참고 웹 링크: https://chatgpt.com/c/example

        사용자 추가 지시: 핵심을 먼저 설명하고 원문 인용과 예외 조건을 보존한다.
        """
      let item = try store.addTextMaterial(title: "글과 도표 작성 요청 · 생성 기록", body: prompt, url: link)
      model.openMaterial(item.id)
      model.materialText = try store.materialExtraction(item.id)
      model.materialTextLoading = false
      XCTAssertEqual(model.openedMaterial?.url, link)
      XCTAssertEqual(model.materialText?.pages.first?.text, prompt)
      XCTAssertTrue(
        Markdown.linkedOriginal(prompt).runs.contains { $0.link?.absoluteString == link })
      let host = NSHostingView(rootView: ContentView(model: model, delegate: AppDelegate()))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1240, height: 830), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      defer {
        window.contentView = nil
        window.close()
      }
      let output = FileManager.default.temporaryDirectory.appendingPathComponent(
        "galpium-chat-link-renders", isDirectory: true)
      try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
      for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
        window.appearance = NSAppearance(named: appearance)
        host.appearance = window.appearance
        for (width, height, size) in [(1240.0, 830.0, "standard"), (900.0, 620.0, "minimum")] {
          window.setContentSize(NSSize(width: width, height: height))
          RunLoop.main.run(until: Date().addingTimeInterval(0.08))
          host.layoutSubtreeIfNeeded()
          let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
          host.cacheDisplay(in: host.bounds, to: bitmap)
          try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
            to: output.appendingPathComponent("\(size)-\(suffix).png"))
        }
      }
    }
  }
  func testSearchRebindingKeepsDetailAndUserSearchReturnsToList() async throws {
    try await MainActor.run {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      let item = try XCTUnwrap(model.store?.addTextMaterial(title: "Original", body: "evidence"))
      model.openMaterial(item.id)
      model.changeMaterialSearch("")
      XCTAssertEqual(model.selectedMaterial, item.id)
      model.changeMaterialSearch("evidence")
      XCTAssertNil(model.selectedMaterial)
      XCTAssertEqual(model.materialQuery, "evidence")
      model.goBack()
      XCTAssertEqual(model.selectedMaterial, item.id)
      XCTAssertEqual(model.materialQuery, "")
    }
  }
  func testNativeCitationInsertionAndRenderedMaterialsAndFootnotes() async throws {
    try await MainActor.run {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      let store = try XCTUnwrap(model.store)
      let material = try store.addTextMaterial(
        title: "한국어 日本語 English 회의록", body: "자료는 기기에 보관됩니다. 引用は原文を保持します。 Evidence is preserved.")
      _ = try store.importMaterial(data: Data("unused notes".utf8), name: "notes.txt")
      model.newPage(material: material)
      let host = NSHostingView(rootView: ContentView(model: model, delegate: AppDelegate()))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1240, height: 830), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      defer {
        window.contentView = nil
        window.close()
      }
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      host.layoutSubtreeIfNeeded()
      let editor = try XCTUnwrap(model.editor.textView)
      editor.setSelectedRange(NSRange(location: 0, length: 0))
      XCTAssertTrue(model.insertCitation(material: material, page: 1, quote: "引用は原文を保持します。"))
      XCTAssertTrue(editor.string.contains("[^ref-"))
      XCTAssertTrue(editor.string.contains("material:" + material.id))
      XCTAssertEqual(model.draft.citations.count, 1)
      XCTAssertTrue(model.save())
      XCTAssertEqual(model.currentPage?.citations.count, 1)
      model.isEditing = false
      @MainActor func capture(_ name: String, _ width: CGFloat, _ height: CGFloat) throws {
        window.setContentSize(NSSize(width: width, height: height))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
          to: URL(fileURLWithPath: "/private/tmp/galpium-materials-" + name + ".png"))
      }
      try capture("footnotes", 1240, 830)
      model.showMaterials()
      try model.refresh()
      XCTAssertEqual(model.sidebarDestination, .materials)
      try capture("minimum", 900, 620)
      try capture("standard", 1240, 830)
      model.materialQuery = "日本語"
      model.startMaterialSearch()
      XCTAssertEqual(try store.searchMaterials(query: "日本語").items.map(\.id), [material.id])
      let count = try store.sources().count
      model.newPage()
      model.draft.title = "직접 작성"
      model.draft.body = "출처 없는 메모"
      XCTAssertTrue(model.save())
      XCTAssertEqual(try store.sources().count, count)
    }
  }
}
