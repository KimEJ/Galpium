import AVFoundation
import AppKit
import GalpiumCore
import PDFKit
import XCTest

@testable import GalpiumApp

final class MaterialSearchNavigationTests: XCTestCase {
  func testVisualSearchOpensPDFPageAndRejectsStaleMatchAfterRename() async throws {
    try await MainActor.run {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      let store = try XCTUnwrap(model.store)
      let document = PDFDocument()
      for color in [NSColor.red, .green, .blue] {
        let image = NSImage(size: NSSize(width: 240, height: 180), flipped: false) { rect in
          color.setFill()
          rect.fill()
          return true
        }
        document.insert(try XCTUnwrap(PDFPage(image: image)), at: document.pageCount)
      }
      let item = try store.importMaterial(
        data: XCTUnwrap(document.dataRepresentation()), name: "charts.pdf")
      model.materialQuery = "blue chart"
      model.materialSearchMatches[item.id] = try Self.match(
        revision: item.revision, modality: "image", page: 3)
      model.openMaterialSearchResult(item)
      XCTAssertEqual(model.selectedMaterial, item.id)
      XCTAssertEqual(model.materialPage, 3)
      XCTAssertEqual(model.materialQuote, "")
      XCTAssertNil(model.materialExtractionID)
      model.showMaterials()
      model.goBack()
      XCTAssertEqual(model.selectedMaterial, item.id)
      XCTAssertEqual(model.materialPage, 3)

      _ = try store.updateMaterial(
        item.id, title: "Renamed charts.pdf", expectedRevision: item.revision)
      model.materialSearchMatches[item.id] = try Self.match(
        revision: item.revision, modality: "image", page: 3)
      model.openMaterialSearchResult(item)
      XCTAssertEqual(model.openedMaterial?.title, "Renamed charts.pdf")
      XCTAssertEqual(model.materialPage, 1)
      XCTAssertEqual(model.materialQuote, "")
    }
  }

  func testAudioSearchKeepsOriginalTimestampThroughNavigationWithoutQuotedTranscript() async throws
  {
    try await MainActor.run {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let model = AppModel(root: root)
      let store = try XCTUnwrap(model.store)
      let fileURL = root.appendingPathComponent("recording.wav")
      let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
      let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160000))
      buffer.frameLength = buffer.frameCapacity
      let channels = try XCTUnwrap(buffer.floatChannelData)
      channels[0].update(repeating: 0, count: Int(buffer.frameLength))
      do {
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try file.write(from: buffer)
      }
      let item = try store.importMaterial(data: Data(contentsOf: fileURL), name: "recording.wav")
      XCTAssertEqual(item.kind, "audio")
      model.materialQuery = "recording"
      model.materialSearchMatches[item.id] = try Self.match(
        revision: item.revision, modality: "audio", start: 4.5, end: 8)
      model.openMaterialSearchResult(item)
      XCTAssertEqual(model.selectedMaterial, item.id)
      XCTAssertEqual(model.materialStartSeconds, 4.5)
      XCTAssertEqual(model.materialQuote, "")
      XCTAssertNil(model.materialExtractionID)
      model.showMaterials()
      model.goBack()
      XCTAssertEqual(model.selectedMaterial, item.id)
      XCTAssertEqual(model.materialStartSeconds, 4.5)

      model.materialQuery = ""
      model.startMaterialSearch()
      XCTAssertTrue(model.materialSearchMatches.isEmpty)
      XCTAssertEqual(model.materials.map(\.id), [item.id])
      model.openMaterialSearchResult(item)
      XCTAssertEqual(model.materialStartSeconds, 0)
    }
  }

  func testAudioMatchTimeRangeFormatting() {
    XCTAssertEqual(MaterialSearchMatchView.timeRange(start: 4.9, end: 20), "0:04–0:20")
    XCTAssertEqual(MaterialSearchMatchView.timeRange(start: 3599, end: 3605), "59:59–1:00:05")
    XCTAssertEqual(MaterialSearchMatchView.timeRange(start: 20, end: 19), "0:20")
    XCTAssertEqual(MaterialSearchMatchView.timeRange(start: .nan, end: .infinity), "0:00")
  }

  private static func match(
    revision: Int, modality: String, page: Int? = nil, start: Double? = nil, end: Double? = nil
  ) throws -> SemanticMatch {
    var value: [String: Any] = [
      "excerpt": "Embedding metadata is not a verbatim quote", "heading": "", "similarity": 0.9,
      "method": modality == "image" ? "visual" : modality, "revision": revision,
      "modality": modality,
    ]
    if let page { value["page"] = page }
    if let start { value["startSeconds"] = start }
    if let end { value["endSeconds"] = end }
    return try JSONDecoder().decode(
      SemanticMatch.self, from: JSONSerialization.data(withJSONObject: value))
  }
}
