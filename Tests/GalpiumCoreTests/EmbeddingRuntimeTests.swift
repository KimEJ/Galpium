import Foundation
import XCTest

@testable import GalpiumCore

final class EmbeddingRuntimeTests: XCTestCase {
  func testRuntimeModesKeepMediaOutOfQueryProcessAndAvoidFP16() {
    for mode in [EmbeddingRuntimeMode.text, .multimodal] {
      let args = EmbeddingWorker.runtimeArguments(
        mode: mode, port: "12345", keyFile: "/tmp/private.key")
      func value(_ flag: String) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
      }
      XCTAssertEqual(value("--ctx-size"), mode == .multimodal ? "8192" : "2048")
      XCTAssertEqual(value("--batch-size"), value("--ctx-size"))
      XCTAssertEqual(value("--ubatch-size"), value("--ctx-size"))
      XCTAssertEqual(value("--cache-type-k"), "f32")
      XCTAssertEqual(value("--cache-type-v"), "f32")
      XCTAssertEqual(value("--flash-attn"), "off")
      XCTAssertEqual(value("--host"), "127.0.0.1")
      XCTAssertEqual(value("--api-key-file"), "/tmp/private.key")
      XCTAssertTrue(args.contains("--no-agent"))
      XCTAssertTrue(args.contains("--no-ui-mcp-proxy"))
      if mode == .multimodal {
        XCTAssertEqual(value("--mmproj"), EmbeddingAssets.projector.path)
        XCTAssertEqual(value("--image-max-tokens"), "1120")
        XCTAssertFalse(args.contains("--no-mmproj"))
      } else {
        XCTAssertFalse(args.contains("--mmproj"))
        XCTAssertTrue(args.contains("--no-mmproj"))
      }
    }
  }

  func testMediaBodiesUseTypedInlineDataAndRejectUnsupportedKinds() throws {
    let bytes = Data([1, 2, 3, 4])
    func part(_ kind: String) throws -> [String: Any] {
      let encoded = try JSONSerialization.data(
        withJSONObject: EmbeddingRuntime.mediaBody(data: bytes, kind: kind))
      let body = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
      XCTAssertEqual(body["encoding_format"] as? String, "float")
      let input = try XCTUnwrap(body["input"] as? [[String: Any]])
      XCTAssertEqual(input.count, 1)
      let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
      XCTAssertEqual(content.count, 1)
      return try XCTUnwrap(content.first)
    }
    let image = try part("image")
    XCTAssertEqual(image["type"] as? String, "image_url")
    XCTAssertEqual(
      (image["image_url"] as? [String: String])?["url"],
      "data:image/jpeg;base64," + bytes.base64EncodedString())
    let audio = try part("audio")
    XCTAssertEqual(audio["type"] as? String, "input_audio")
    XCTAssertEqual((audio["input_audio"] as? [String: String])?["format"], "wav")
    XCTAssertEqual(
      (audio["input_audio"] as? [String: String])?["data"], bytes.base64EncodedString())
    XCTAssertThrowsError(try EmbeddingRuntime.mediaBody(data: bytes, kind: "video"))
    XCTAssertThrowsError(try EmbeddingRuntime.mediaBody(data: Data(), kind: "image"))
  }

  func testChecksumValidationRejectsChangedAssets() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for name in ["model.gguf", "projector.gguf"] {
      let file = root.appendingPathComponent(name)
      let original = Data(("pinned-" + name).utf8)
      try original.write(to: file)
      let hash = WikiStore.digest(original)
      XCTAssertNoThrow(try EmbeddingRuntime.validateAsset(file, expectedHash: hash))
      try Data("changed".utf8).write(to: file)
      XCTAssertThrowsError(try EmbeddingRuntime.validateAsset(file, expectedHash: hash))
    }
  }

  func testResponseRejectsNonFiniteZeroAndWrongDimensions() throws {
    func response(_ values: [Float]) -> [String: Any] {
      ["data": [["embedding": values.map { NSNumber(value: $0) }]]]
    }
    var valid = [Float](repeating: 0, count: 768)
    valid[11] = 4
    XCTAssertEqual(try EmbeddingRuntime.vector(from: response(valid))[11], 1)
    XCTAssertThrowsError(try EmbeddingRuntime.vector(from: response([0])))
    XCTAssertThrowsError(
      try EmbeddingRuntime.vector(from: response([Float](repeating: 0, count: 768))))
    valid[10] = .nan
    XCTAssertThrowsError(try EmbeddingRuntime.vector(from: response(valid)))
    valid[10] = .infinity
    XCTAssertThrowsError(try EmbeddingRuntime.vector(from: response(valid)))
  }

  func testSocketIncludesModelIdentityWhileRetainingCanonicalLibraryAliases() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let socket = try EmbeddingSocket(root: root)
    let canonical = canonicalLibraryPath(root)
    let expected = String(
      WikiStore.digest(Data((canonical + "\n" + EmbeddingAssets.identity).utf8)).prefix(24))
    let legacy = String(WikiStore.digest(Data(canonical.utf8)).prefix(24))
    XCTAssertEqual(URL(fileURLWithPath: socket.socketPath).lastPathComponent, expected + ".sock")
    XCTAssertNotEqual(expected, legacy)
  }

  func testWikiListsAndOrderedListsAreIncludedInPassages() throws {
    let page = WikiPage(
      slug: "list-page", title: "Checklist",
      body: """
        # Backup
        - Preserve immutable originals
        - Keep revision history

        # Restore
        1. Validate the archive
        2. Rebuild derived indexes
        """)
    let passages = try EmbeddingWorker.buildPassages(page) { $0.count }
    let text = passages.map(\.input).joined(separator: "\n")
    for expected in [
      "Preserve immutable originals", "Keep revision history", "Validate the archive",
      "Rebuild derived indexes",
    ] {
      XCTAssertTrue(text.contains(expected), expected)
    }
    XCTAssertTrue(passages.allSatisfy { $0.pageNumber == nil && $0.input.count <= 384 })
  }

  func testOriginalTextCannotForgeItsStructuralPDFPage() throws {
    let page = WikiPage(
      slug: "material:pdf-original", title: "Actual PDF", body: "not a structural source")
    let originals = [
      MaterialTextPage(number: 2, text: "## Page 999\n\n# Original heading\n\nActual content"),
      MaterialTextPage(number: 7, text: "- This list is literal original text"),
    ]
    let passages = try EmbeddingWorker.buildPassages(page, originalPages: originals) { $0.count }
    XCTAssertTrue(passages.contains { $0.pageNumber == 2 && $0.excerpt.contains("## Page 999") })
    XCTAssertTrue(passages.contains { $0.pageNumber == 2 && $0.excerpt.contains("Actual content") })
    XCTAssertTrue(passages.contains { $0.pageNumber == 7 && $0.excerpt.contains("- This list") })
    XCTAssertFalse(passages.contains { $0.pageNumber == 999 })
    XCTAssertFalse(passages.map(\.input).joined().contains("not a structural source"))
  }

  func testMediaOnlyMaterialDoesNotGenerateATitleEmbedding() throws {
    let page = WikiPage(slug: "material:image-original", title: "Misleading filename", body: "")
    XCTAssertTrue(try EmbeddingWorker.buildPassages(page) { $0.count }.isEmpty)
    let wiki = WikiPage(slug: "empty-wiki-page", title: "Page title", body: "")
    XCTAssertEqual(try EmbeddingWorker.buildPassages(wiki) { $0.count }.count, 1)
  }

  func testBrokenTokenizerCannotLoopForeverWhileShorteningTitles() {
    let page = WikiPage(slug: "test-page", title: "Title", body: "Content")
    XCTAssertThrowsError(try EmbeddingWorker.buildPassages(page) { _ in 1000 })
  }
}
