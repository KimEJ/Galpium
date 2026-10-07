import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest

@testable import GalpiumCore

final class SemanticMediaTests: XCTestCase {
  private func store() throws -> WikiStore {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    return try WikiStore(root: root)
  }

  private func image(width: Int = 4000, height: Int = 1000) throws -> Data {
    let context = try XCTUnwrap(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 0.7))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
  }

  private func pdf() throws -> Data {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 400, height: 600)
    let context = try XCTUnwrap(
      CGContext(
        consumer: XCTUnwrap(CGDataConsumer(data: data)), mediaBox: &box, nil))
    for color in [
      CGColor(red: 1, green: 0, blue: 0, alpha: 1),
      CGColor(red: 0, green: 0, blue: 1, alpha: 1),
    ] {
      context.beginPDFPage(nil)
      context.setFillColor(color)
      context.fill(CGRect(x: 20, y: 20, width: 350, height: 500))
      context.endPDFPage()
    }
    context.closePDF()
    return data as Data
  }

  private func wav(seconds: Double, sampleRate: Int = 48_000, channels: Int = 2) -> Data {
    let frames = Int(seconds * Double(sampleRate))
    var data = Data("RIFF".utf8)
    func u32(_ value: Int) {
      var word = UInt32(value).littleEndian
      withUnsafeBytes(of: &word) { data.append(contentsOf: $0) }
    }
    func u16(_ value: Int) {
      var word = UInt16(value).littleEndian
      withUnsafeBytes(of: &word) { data.append(contentsOf: $0) }
    }
    u32(36 + frames * channels * 2)
    data.append(Data("WAVEfmt ".utf8))
    u32(16)
    u16(1)
    u16(channels)
    u32(sampleRate)
    u32(sampleRate * channels * 2)
    u16(channels * 2)
    u16(16)
    data.append(Data("data".utf8))
    u32(frames * channels * 2)
    for frame in 0..<frames {
      let sample = Int16(
        (sin(Double(frame) * 2 * .pi * 440 / Double(sampleRate)) * 12_000).rounded())
      for _ in 0..<channels {
        var word = sample.littleEndian
        withUnsafeBytes(of: &word) { data.append(contentsOf: $0) }
      }
    }
    return data
  }

  private func imageSize(_ data: Data) throws -> (Int, Int) {
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return (image.width, image.height)
  }

  func testImageIndexingBoundsOriginalPreservationAndNoInventedQuote() throws {
    let db = try store()
    let original = try image()
    let material = try db.importMaterial(data: original, name: "chart.png")
    let key = "material:" + material.id
    let document = try db.semanticDocument(key)
    XCTAssertEqual(document.body, "")
    XCTAssertEqual(try db.semanticRevisions()[key], 1)
    let media = try XCTUnwrap(db.semanticMediaItems(key).first)
    XCTAssertEqual(media.kind, "image")
    XCTAssertNil(media.pageNumber)
    XCTAssertEqual(media.originalHash, WikiStore.digest(original))
    let jpeg = try db.semanticMediaData(media)
    let size = try imageSize(jpeg)
    XCTAssertEqual(size.0, 2048)
    XCTAssertEqual(size.1, 512)
    XCTAssertNil(try db.materialExtraction(material.id))
    XCTAssertThrowsError(
      try db.makeCitation(
        materialID: material.id, page: 1, quote: "invented OCR", id: "fake"))
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(db.materialFileURL(material))), original)
    XCTAssertEqual(
      try WikiJSON.decoder().decode(
        SemanticMediaItem.self, from: WikiJSON.encoder().encode(media)), media)

    let renamed = try db.updateMaterial(material.id, title: "renamed.png", expectedRevision: 1)
    XCTAssertEqual(try db.semanticMediaItems(key).first?.id, media.id)
    XCTAssertEqual(try db.semanticDocument(key).revision, renamed.revision)
    let archived = try db.updateMaterial(material.id, status: "archived", expectedRevision: 2)
    XCTAssertEqual(archived.revision, 3)
    XCTAssertNil(try db.semanticRevisions()[key])
    XCTAssertThrowsError(try db.semanticMediaItems(key))
    XCTAssertThrowsError(try db.semanticMediaData(media))
    XCTAssertThrowsError(try db.semanticDocument(key))
  }

  func testScannedPDFIncludesEveryPageWithoutCreatingTextEvidence() throws {
    let db = try store()
    let original = try pdf()
    let material = try db.importMaterial(data: original, name: "scan.pdf")
    let key = "material:" + material.id
    XCTAssertEqual(try db.materialExtraction(material.id)?.pages, [])
    XCTAssertEqual(try db.semanticDocument(key).body, "")
    // An existing empty text extraction must not exclude a visual PDF from indexing.
    XCTAssertEqual(try db.semanticRevisions()[key], 1)
    let items = try db.semanticMediaItems(key)
    XCTAssertEqual(items.map(\.pageNumber), [1, 2])
    XCTAssertEqual(Set(items.map(\.id)).count, 2)
    for item in items {
      let size = try imageSize(db.semanticMediaData(item))
      XCTAssertLessThanOrEqual(max(size.0, size.1), 2048)
      XCTAssertEqual(Double(size.0) / Double(size.1), 2 / 3, accuracy: 0.002)
    }
    XCTAssertNotEqual(try db.semanticMediaData(items[0]), try db.semanticMediaData(items[1]))
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(db.materialFileURL(material))), original)
    XCTAssertThrowsError(
      try db.makeCitation(
        materialID: material.id, page: 1, quote: "a red figure", id: "fake"))
    var invalidPage = items[0]
    invalidPage.pageNumber = 3
    XCTAssertThrowsError(try db.semanticMediaData(invalidPage))
  }

  func testInvalidLockedAndTamperedMediaFailIndependently() throws {
    let db = try store()
    for name in ["broken.png", "broken.pdf", "broken.wav"] {
      let material = try db.importMaterial(data: Data("invalid".utf8), name: name)
      let key = "material:" + material.id
      XCTAssertEqual(try db.semanticRevisions()[key], 1)
      XCTAssertThrowsError(try db.semanticMediaItems(key))
    }
    let document = try XCTUnwrap(PDFDocument(data: pdf()))
    let locked = try XCTUnwrap(
      document.dataRepresentation(options: [
        PDFDocumentWriteOption.ownerPasswordOption: "owner",
        PDFDocumentWriteOption.userPasswordOption: "secret",
      ]))
    let lockedMaterial = try db.importMaterial(data: locked, name: "locked.pdf")
    XCTAssertThrowsError(try db.semanticMediaItems("material:" + lockedMaterial.id))

    let valid = try db.importMaterial(data: image(width: 100, height: 100), name: "valid.png")
    let media = try XCTUnwrap(db.semanticMediaItems("material:" + valid.id).first)
    XCTAssertFalse(try db.semanticMediaData(media).isEmpty)
    try Data("changed original".utf8).write(to: XCTUnwrap(db.materialFileURL(valid)))
    XCTAssertThrowsError(try db.semanticMediaData(media))
    XCTAssertThrowsError(try db.semanticMediaItems("material:" + valid.id))
    XCTAssertThrowsError(try db.semanticDocument("material:" + valid.id))
  }

  func testAudioAllChunksHaveTimeLocationsAndBoundedMonoWAV() throws {
    let db = try store()
    let original = wav(seconds: 21.25)
    let material = try db.importMaterial(data: original, name: "recording.wav")
    XCTAssertEqual(material.kind, "audio")
    XCTAssertEqual(try db.materials(kind: "audio").map(\.id), [material.id])
    let key = "material:" + material.id
    XCTAssertEqual(try db.semanticDocument(key).body, "")
    XCTAssertNil(try db.materialExtraction(material.id))
    let chunks = try db.semanticMediaItems(key)
    XCTAssertEqual(chunks.count, 2)
    XCTAssertEqual(chunks.map(\.startSeconds), [0, 20])
    XCTAssertEqual(chunks.map(\.endSeconds), [20, 21.25])
    XCTAssertNotEqual(chunks[0].identity, chunks[1].identity)
    for chunk in chunks {
      let data = try db.semanticMediaData(chunk)
      XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
      let rate = data.withUnsafeBytes {
        UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 24, as: UInt32.self))
      }
      let channelCount = data.withUnsafeBytes {
        UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: 22, as: UInt16.self))
      }
      XCTAssertEqual(rate, 16_000)
      XCTAssertEqual(channelCount, 1)
      XCTAssertGreaterThan(data.count, 44)
      XCTAssertLessThanOrEqual(data.count, 44 + 20 * 16_000 * 2)
      XCTAssertEqual(
        Double(data.count - 44) / 32_000, chunk.endSeconds! - chunk.startSeconds!, accuracy: 0.02)
    }
    var invalid = chunks[0]
    invalid.startSeconds = 1
    XCTAssertThrowsError(try db.semanticMediaData(invalid))
    XCTAssertThrowsError(
      try db.makeCitation(
        materialID: material.id, page: 1, quote: "invented transcript", id: "fake"))
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(db.materialFileURL(material))), original)

    // Existing libraries used kind=file for audio. Reading/filtering recognizes
    // those records without changing persisted metadata or their revision.
    var legacy = material
    legacy.kind = "file"
    let raw = try WikiJSON.encode(legacy)
    try db.db.execute("UPDATE materials SET data=? WHERE id=?", [raw, material.id])
    XCTAssertEqual(try db.material(material.id).kind, "audio")
    XCTAssertEqual(try db.materials(kind: "audio").map(\.id), [material.id])
    XCTAssertEqual(
      try db.db.query("SELECT data FROM materials WHERE id=?", [material.id])[0][0], raw)
  }

  func testOrdinaryWikiPageDoesNotDuplicateLinkedVisualIndex() throws {
    let db = try store()
    let material = try db.importMaterial(data: image(width: 100, height: 100), name: "figure.png")
    let page = try db.upsert(
      WikiPage(
        slug: "notes", title: "Notes", body: "[Figure](material:\(material.id))",
        materials: [material.id]), expectedRevision: 0)
    XCTAssertEqual(try db.semanticMediaItems(page.slug), [])
    XCTAssertEqual(try db.semanticDocument(page.slug), page)
  }

  func testSilentAudioIsValidButZeroFrameAudioFails() throws {
    let db = try store()
    var silent = wav(seconds: 0.25, sampleRate: 16_000, channels: 1)
    silent.replaceSubrange(44..<silent.count, with: Data(repeating: 0, count: silent.count - 44))
    let material = try db.importMaterial(data: silent, name: "pause.wav")
    let item = try XCTUnwrap(db.semanticMediaItems("material:" + material.id).first)
    let converted = try db.semanticMediaData(item)
    XCTAssertGreaterThan(converted.count, 44)
    XCTAssertTrue(converted.dropFirst(44).allSatisfy { $0 == 0 })
    let empty = try db.importMaterial(data: wav(seconds: 0), name: "empty.wav")
    XCTAssertThrowsError(try db.semanticMediaItems("material:" + empty.id))
  }
}
