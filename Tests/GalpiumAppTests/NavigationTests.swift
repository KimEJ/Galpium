import AppKit
import GalpiumCore
import SwiftUI
import XCTest

@testable import GalpiumApp

final class NavigationTests: XCTestCase {
  func testAttachmentsDestinationRestoresFilenameSearchAndRefreshesExternalLinks() async throws {
    try await MainActor.run {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      let store = try XCTUnwrap(model.store)
      let file = try store.attach(data: Data("report".utf8), name: "日本語.pdf")
      model.search = "wiki query"
      model.showArchive()
      model.showAttachments()
      model.attachmentQuery = "日本語"
      try model.refresh()
      XCTAssertEqual(model.sidebarDestination, .materials)
      XCTAssertNil(model.currentPage)
      XCTAssertNil(model.currentSource)
      XCTAssertEqual(model.inspector, "")
      XCTAssertEqual(model.filteredAttachments.map(\.id), [file.id])
      XCTAssertEqual(model.materialLinkCounts[WikiMaterial.fileID(file.id), default: 0], 0)
      model.home()
      model.attachmentQuery = "different query"
      let other = try WikiStore(root: root)
      let original = try other.ingest(slug: "original", title: "Original", body: "original text")
      _ = try other.upsert(
        WikiPage(
          slug: "external", title: "External", body: "[file](attachment:\(file.id))",
          sources: [original.slug]),
        expectedRevision: 0)
      model.goBack()
      XCTAssertEqual(model.sidebarDestination, .materials)
      XCTAssertEqual(model.attachmentQuery, "日本語")
      XCTAssertEqual(model.search, "wiki query")
      XCTAssertEqual(model.materialLinkCounts[WikiMaterial.fileID(file.id)], 1)
      model.goForward()
      XCTAssertEqual(model.sidebarDestination, .wiki)
      model.isRenamingAttachment = true
      model.showAttachments()
      XCTAssertEqual(model.sidebarDestination, .wiki)
    }
  }
  func testAttachmentsMainViewRendersAtMinimumAndStandardWindowSizes() async throws {
    try await MainActor.run {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      let store = try XCTUnwrap(model.store)
      let file = try store.attach(
        data: Data("report".utf8), name: "日本語_한국어_Research notes and references.pdf")
      _ = try store.attach(data: Data("unused".utf8), name: "notes.txt")
      _ = try store.ingest(
        slug: "original", title: "Original", body: "[file](attachment:\(file.id))")
      model.showAttachments()
      try model.refresh()
      let delegate = AppDelegate()
      for (name, size) in [
        ("minimum", NSSize(width: 900, height: 620)),
        ("standard", NSSize(width: 1200, height: 800)),
      ] {
        let host = NSHostingView(rootView: ContentView(model: model, delegate: delegate))
        let window = NSWindow(
          contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered,
          defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
          window.contentView = nil
          window.close()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/private/tmp/galpium-attachments-" + name + ".png"))
        XCTAssertGreaterThan(png.count, 1000)
      }
      XCTAssertEqual(model.section, "materials")
      XCTAssertEqual(model.inspector, "")
      XCTAssertEqual(model.materialLinkCounts[WikiMaterial.fileID(file.id)], 1)
    }
  }
  func testSwipeAnimationRendersDifferentProgressWithoutChangingDocument() async throws {
    try await MainActor.run {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      _ = try model.store?.upsert(
        WikiPage(slug: "animation-proof", title: "스와이프 확인", body: "문서 영역의 이동을 확인합니다."),
        expectedRevision: 0, preserveOriginal: true)
      model.open(try XCTUnwrap(model.store?.page("animation-proof")))
      let delegate = AppDelegate()
      let host = NSHostingView(rootView: ContentView(model: model, delegate: delegate))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      defer {
        window.contentView = nil
        window.close()
      }
      @MainActor func render(_ amount: CGFloat, name: String) throws -> Data {
        model.swipePresentation.update(amount)
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        host.layoutSubtreeIfNeeded()
        let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: image)
        let data = try XCTUnwrap(image.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/private/tmp/galpium-swipe-" + name + ".png"))
        return data
      }
      let idle = try render(0, name: "idle")
      let moving = try render(0.5, name: "moving")
      XCTAssertNotEqual(idle, moving)
      XCTAssertEqual(model.currentPage?.slug, "animation-proof")
    }
  }
  func testSwipePresentationTracksCancelsCommitsAndResetsForBothDirections() async throws {
    await MainActor.run {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      model.showSources()
      let responder = NavigationGestureResponder()
      responder.model = model
      responder.tracking = true
      responder.completeSwipe(amount: 0.35, phase: .changed, complete: false, backSign: 1)
      XCTAssertEqual(model.swipePresentation.amount, 0.35, accuracy: 0.001)
      XCTAssertEqual(model.section, "materials")
      responder.completeSwipe(amount: 0.1, phase: .cancelled, complete: false, backSign: 1)
      responder.completeSwipe(amount: 0, phase: [], complete: true, backSign: 1)
      XCTAssertEqual(model.swipePresentation.amount, 0)
      XCTAssertEqual(model.section, "materials")
      responder.tracking = true
      responder.completeSwipe(amount: -0.4, phase: .changed, complete: false, backSign: -1)
      XCTAssertEqual(model.swipePresentation.amount, 0.4, accuracy: 0.001)
      responder.completeSwipe(amount: -1, phase: [], complete: true, backSign: -1)
      XCTAssertEqual(model.section, "home")
      XCTAssertEqual(model.swipePresentation.amount, 0)
      responder.tracking = true
      responder.completeSwipe(amount: -0.4, phase: .changed, complete: false, backSign: 1)
      XCTAssertEqual(model.swipePresentation.amount, -0.4, accuracy: 0.001)
      responder.completeSwipe(amount: -1, phase: [], complete: true, backSign: 1)
      XCTAssertEqual(model.section, "materials")
      XCTAssertEqual(model.swipePresentation.amount, 0)
      responder.tracking = true
      responder.completeSwipe(amount: 0.5, phase: .changed, complete: false, backSign: 1)
      model.isEditing = true
      responder.completeSwipe(amount: 0.8, phase: .changed, complete: false, backSign: 1)
      XCTAssertFalse(responder.tracking)
      XCTAssertEqual(model.swipePresentation.amount, 0)
      XCTAssertEqual(model.section, "materials")
    }
  }
  func testBackForwardRestoresFiltersAndReadsCurrentMCPRevision() async throws {
    try await MainActor.run {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      let store = try XCTUnwrap(model.store)
      let source = try store.ingest(slug: "original", title: "Original", body: "text")
      var page = try store.upsert(
        WikiPage(
          slug: "page", title: "Page", body: "first", sources: [source.slug], tags: ["work"]),
        expectedRevision: 0)
      model.tag = "work"
      model.search = "first"
      model.open(page)
      model.openSource(source.slug)
      let writer = try WikiStore(root: root)
      page.body = "updated through MCP"
      _ = try writer.upsert(page, expectedRevision: 1)
      model.goBack()
      XCTAssertEqual(model.currentPage?.body, "updated through MCP")
      XCTAssertEqual(model.currentPage?.revision, 2)
      XCTAssertEqual(model.tag, "work")
      XCTAssertEqual(model.search, "first")
      model.goForward()
      XCTAssertEqual(model.openedMaterial?.sourceSlug, source.slug)
      model.goBack()
      model.home()
      XCTAssertFalse(model.canGoForward)
      model.goBack()
      XCTAssertEqual(model.currentPage?.slug, page.slug)
    }
  }
  func testGestureCancellationBusyAndEditingDoNotNavigate() async throws {
    await MainActor.run {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      model.showSources()
      let responder = NavigationGestureResponder()
      responder.model = model
      responder.tracking = true
      responder.completeSwipe(amount: 0.8, phase: .cancelled, complete: false, backSign: 1)
      responder.completeSwipe(amount: 1, phase: [], complete: true, backSign: 1)
      XCTAssertEqual(model.section, "materials")
      responder.tracking = true
      responder.completeSwipe(amount: 1, phase: [], complete: true, backSign: 1)
      XCTAssertEqual(model.section, "home")
      responder.completeSwipe(amount: 1, phase: [], complete: true, backSign: 1)
      XCTAssertEqual(model.backLocations.count, 0)
      model.isBusy = true
      model.goForward()
      XCTAssertEqual(model.section, "home")
      model.isBusy = false
      model.goForward()
      XCTAssertEqual(model.section, "materials")
      model.isRenamingAttachment = true
      model.goBack()
      XCTAssertEqual(model.section, "materials")
      model.isRenamingAttachment = false
      model.newPage()
      XCTAssertFalse(model.canGoBack)
      model.goBack()
      XCTAssertTrue(model.isEditing)
    }
  }
  func testNativeGestureBridgeRestoresResponderChainAndFilenameSearch() async throws {
    try await MainActor.run {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      _ = try model.store?.attach(data: Data("report".utf8), name: "Résumé.txt")
      _ = try model.store?.attach(data: Data("other".utf8), name: "日本語.pdf")
      try model.refresh()
      model.attachmentQuery = "RÉSUMÉ"
      XCTAssertEqual(model.filteredAttachments.map(\.name), ["Résumé.txt"])
      model.attachmentQuery = "日本語"
      XCTAssertEqual(model.filteredAttachments.map(\.name), ["日本語.pdf"])
      let file = try XCTUnwrap(model.filteredAttachments.first)
      XCTAssertTrue(model.renameAttachment(file, name: "新しい名前.pdf"))
      XCTAssertEqual(model.attachmentQuery, "")
      model.attachmentQuery = "新しい"
      XCTAssertEqual(model.filteredAttachments.map(\.name), ["新しい名前.pdf"])
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      let previous = NSResponder()
      window.nextResponder = previous
      let view = NavigationGestureView()
      window.contentView = view
      XCTAssertTrue(window.nextResponder === view.navigator)
      window.contentView = NSView()
      XCTAssertTrue(window.nextResponder === previous)
      window.close()
    }
  }
}
