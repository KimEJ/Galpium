import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A lightweight location in an immutable original, never OCR or a quotation.
/// Pixels and PCM are generated only when the worker processes this one item.
struct SemanticMediaItem: Codable, Equatable, Sendable {
  enum CodingKeys: String, CodingKey {
    case originalHash, kind, pageNumber, startSeconds, endSeconds
    case materialID = "materialId"
  }
  var materialID: String
  var originalHash: String
  var kind: String
  var pageNumber: Int? = nil
  var startSeconds: Double? = nil
  var endSeconds: Double? = nil

  var identity: String {
    let location =
      pageNumber.map(String.init)
      ?? "\(startSeconds ?? 0):\(endSeconds ?? 0)"
    let method = kind == "audio" ? "wav16000mono16-v1" : "jpeg2048-v1"
    return WikiStore.digest(Data((originalHash + ":" + kind + ":" + method + ":" + location).utf8))
  }
  var id: String { identity }
  // Location is represented by page/time metadata, not fabricated source prose.
  var heading: String { "" }
  var excerpt: String { "" }
}

extension WikiStore {
  func semanticMediaItems(_ key: String) throws -> [SemanticMediaItem] {
    guard key.hasPrefix("material:") else { return [] }
    let material = try material(String(key.dropFirst(9)))
    guard material.status == "active" else { throw WikiError.notFound("active material") }
    guard ["image", "pdf", "audio"].contains(material.kind) else { return [] }
    let data = try semanticOriginalData(material)
    switch material.kind {
    case "image":
      guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        CGImageSourceGetCount(source) > 0
      else { throw WikiError.invalid("image") }
      return [
        SemanticMediaItem(
          materialID: material.id, originalHash: material.originalHash, kind: "image")
      ]
    case "pdf":
      let document = try semanticPDF(data)
      // Reject corrupt resource counts rather than silently dropping later pages.
      guard document.numberOfPages > 0, document.numberOfPages <= 100_000 else {
        throw WikiError.invalid("PDF page count")
      }
      return (1...document.numberOfPages).map {
        SemanticMediaItem(
          materialID: material.id, originalHash: material.originalHash, kind: "image",
          pageNumber: $0)
      }
    case "audio":
      let file = try semanticAudioFile(material)
      let duration = Double(file.length) / file.processingFormat.sampleRate
      guard duration.isFinite, duration > 0, ceil(duration / 20) <= 100_000 else {
        throw WikiError.invalid("audio duration")
      }
      return (0..<Int(ceil(duration / 20))).map {
        SemanticMediaItem(
          materialID: material.id, originalHash: material.originalHash, kind: "audio",
          startSeconds: Double($0) * 20, endSeconds: min(Double($0 + 1) * 20, duration))
      }
    default: return []
    }
  }

  func semanticMediaData(_ item: SemanticMediaItem) throws -> Data {
    try Task.checkCancellation()
    let material = try material(item.materialID)
    guard material.status == "active", material.originalHash == item.originalHash else {
      throw WikiError.invalid("media original or status")
    }
    let data = try semanticOriginalData(material)
    if item.kind == "audio", material.kind == "audio" {
      guard item.pageNumber == nil else { throw WikiError.invalid("audio location") }
      let result = try semanticWAV(material, start: item.startSeconds, end: item.endSeconds)
      // AVAudioFile reads by URL; check again after decoding to detect a changed original.
      try verifyOriginal(material)
      return result
    }
    guard item.kind == "image", item.startSeconds == nil, item.endSeconds == nil else {
      throw WikiError.invalid("media kind")
    }
    let image: CGImage
    if material.kind == "pdf", let number = item.pageNumber {
      let document = try semanticPDF(data)
      guard number > 0, let page = document.page(at: number) else {
        throw WikiError.invalid("PDF page")
      }
      image = try semanticPDFImage(page)
    } else if material.kind == "image", item.pageNumber == nil {
      guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(
          source, 0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldCache: false,
          ] as CFDictionary)
      else { throw WikiError.invalid("image decode") }
      image = thumbnail
    } else {
      throw WikiError.invalid("media location")
    }
    // Composite transparent pixels onto white before JPEG; diagrams often contain alpha.
    guard
      let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw WikiError.invalid("image canvas") }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let flattened = context.makeImage() else { throw WikiError.invalid("image canvas") }
    let result = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        result, UTType.jpeg.identifier as CFString, 1, nil)
    else { throw WikiError.invalid("JPEG destination") }
    CGImageDestinationAddImage(
      destination, flattened, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw WikiError.invalid("JPEG encoding") }
    return result as Data
  }

  private func semanticOriginalData(_ material: WikiMaterial) throws -> Data {
    guard let url = try materialFileURL(material) else { throw WikiError.notFound("media file") }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    guard Self.digest(data) == material.originalHash else {
      throw WikiError.invalid("original checksum")
    }
    return data
  }

  private func semanticPDF(_ data: Data) throws -> CGPDFDocument {
    guard let provider = CGDataProvider(data: data as CFData),
      let document = CGPDFDocument(provider), !document.isEncrypted || document.isUnlocked
    else { throw WikiError.invalid("PDF") }
    return document
  }

  private func semanticPDFImage(_ page: CGPDFPage) throws -> CGImage {
    let box = page.getBoxRect(.cropBox)
    guard box.width.isFinite, box.height.isFinite, box.minX.isFinite, box.minY.isFinite,
      box.width > 0, box.height > 0
    else {
      throw WikiError.invalid("PDF page bounds")
    }
    let rotated = page.rotationAngle % 180 == 90 || page.rotationAngle % 180 == -90
    let width = rotated ? box.height : box.width
    let height = rotated ? box.width : box.height
    let longest = max(width, height)
    let pixelWidth = min(2048, max(1, Int(ceil(width / longest * 2048))))
    let pixelHeight = min(2048, max(1, Int(ceil(height / longest * 2048))))
    guard
      let context = CGContext(
        data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
        bytesPerRow: pixelWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw WikiError.invalid("PDF canvas") }
    let bounds = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(bounds)
    let transform = page.getDrawingTransform(
      .cropBox, rect: bounds, rotate: 0, preserveAspectRatio: true)
    guard
      [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty]
        .allSatisfy(\.isFinite)
    else { throw WikiError.invalid("PDF transform") }
    context.concatenate(transform)
    context.drawPDFPage(page)
    guard let image = context.makeImage() else { throw WikiError.invalid("PDF render") }
    return image
  }

  private func semanticAudioFile(_ material: WikiMaterial) throws -> AVAudioFile {
    guard let url = try materialFileURL(material) else { throw WikiError.notFound("audio file") }
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    guard format.sampleRate.isFinite, (8_000...384_000).contains(format.sampleRate),
      format.channelCount > 0, format.channelCount <= 32, file.length > 0
    else { throw WikiError.invalid("audio format") }
    return file
  }

  private func semanticWAV(_ material: WikiMaterial, start: Double?, end: Double?) throws -> Data {
    let file = try semanticAudioFile(material)
    let sourceRate = file.processingFormat.sampleRate
    let duration = Double(file.length) / sourceRate
    guard let start, let end, start.isFinite, end.isFinite,
      start >= 0, end > start, end <= duration + 1 / sourceRate, end - start <= 20.000_001,
      abs((start / 20).rounded() - start / 20) < 0.000_001
    else { throw WikiError.invalid("audio interval") }
    let firstFrame = AVAudioFramePosition((start * sourceRate).rounded())
    let lastFrame = min(file.length, AVAudioFramePosition((end * sourceRate).rounded()))
    guard firstFrame >= 0, firstFrame < lastFrame else { throw WikiError.invalid("audio interval") }
    file.framePosition = firstFrame
    guard let target = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
      let converter = AVAudioConverter(from: file.processingFormat, to: target),
      let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 8192)
    else { throw WikiError.invalid("audio conversion") }
    converter.downmix = true
    var remaining = lastFrame - firstFrame
    var readError: Error?
    var pcm = Data()
    let maximumFrames = Int(ceil((end - start) * 16_000))
    pcm.reserveCapacity(maximumFrames * 2)
    var loops = 0
    while true {
      try Task.checkCancellation()
      output.frameLength = 0
      var conversionError: NSError?
      let status = converter.convert(to: output, error: &conversionError) { requested, state in
        guard remaining > 0 else {
          state.pointee = .endOfStream
          return nil
        }
        let count = AVAudioFrameCount(min(remaining, Int64(max(1, min(requested, 4096)))))
        guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count)
        else {
          readError = WikiError.invalid("audio buffer")
          state.pointee = .endOfStream
          return nil
        }
        do {
          try Task.checkCancellation()
          try file.read(into: input, frameCount: count)
          guard input.frameLength > 0 else { throw WikiError.invalid("truncated audio") }
          remaining -= Int64(input.frameLength)
          state.pointee = .haveData
          return input
        } catch {
          readError = error
          state.pointee = .endOfStream
          return nil
        }
      }
      if let readError { throw readError }
      if let conversionError { throw conversionError }
      guard status != .error else { throw WikiError.invalid("audio conversion") }
      guard let samples = output.floatChannelData?[0] else {
        throw WikiError.invalid("audio samples")
      }
      for index in 0..<Int(output.frameLength) where pcm.count / 2 < maximumFrames {
        guard samples[index].isFinite else { throw WikiError.invalid("audio samples") }
        var sample = Int16((max(-1, min(1, samples[index])) * 32767).rounded()).littleEndian
        withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
      }
      loops += 1
      guard loops < 100 else { throw WikiError.invalid("audio conversion stalled") }
      if status == .endOfStream || (status == .inputRanDry && remaining == 0) { break }
    }
    guard !pcm.isEmpty, remaining == 0 else { throw WikiError.invalid("empty audio interval") }
    var wav = Data("RIFF".utf8)
    func append32(_ value: UInt32) {
      var value = value.littleEndian
      withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) }
    }
    func append16(_ value: UInt16) {
      var value = value.littleEndian
      withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) }
    }
    append32(UInt32(36 + pcm.count))
    wav.append(Data("WAVEfmt ".utf8))
    append32(16)
    append16(1)
    append16(1)
    append32(16_000)
    append32(32_000)
    append16(2)
    append16(16)
    wav.append(Data("data".utf8))
    append32(UInt32(pcm.count))
    wav.append(pcm)
    return wav
  }
}
