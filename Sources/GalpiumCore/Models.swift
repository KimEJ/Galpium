import Foundation

public enum WikiError: Error, LocalizedError, Equatable {
  case invalid(String)
  case notFound(String)
  case conflict(Int)
  case immutable
  case attachmentInUse
  case storage(String)
  public var errorDescription: String? {
    switch self {
    case .invalid(let field): return localized("입력 값을 확인해 주세요: %@", field)
    case .notFound(let item): return localized("찾을 수 없습니다: %@", item)
    case .conflict(let revision):
      return localized("다른 곳에서 문서가 변경되었습니다. 최신 r%ld과 비교한 뒤 저장하세요.", revision)
    case .immutable: return localized("원본 자료는 덮어쓸 수 없습니다. 새 원본으로 추가하세요.")
    case .attachmentInUse:
      return localized("위키에서 사용되는 첨부파일은 삭제할 수 없습니다.")
    case .storage(let message): return localized("저장소 오류: %@", message)
    }
  }
}

public struct WikiSource: Codable, Identifiable, Equatable, Sendable {
  public var id: String { slug }
  public var slug: String
  public var title: String
  public var body: String
  public var url: String
  public var createdAt: String
  public var sha256: String?
}

public struct PageSummary: Codable, Identifiable, Sendable {
  public var id: String { slug }
  public var slug: String
  public var title: String
  public var excerpt: String
  public var sources: [String]
  public var tags: [String]
  public var pinned: Bool
  public var status: String
  public var revision: Int
  public var createdAt: String
  public var updatedAt: String
}
public struct SourceSummary: Codable, Identifiable, Sendable {
  public var id: String { slug }
  public var slug: String
  public var title: String
  public var excerpt: String
  public var createdAt: String
}

public struct WikiPage: Codable, Identifiable, Equatable, Sendable {
  public var id: String { slug }
  public var slug: String
  public var title: String
  public var body: String
  public var sources: [String]
  public var materials: [String]
  public var citations: [WikiCitation]
  public var tags: [String]
  public var pinned: Bool
  public var status: String
  public var revision: Int
  public var operation: String
  public var changeNote: String
  public var createdAt: String
  public var updatedAt: String
  public var restoredFromRevision: Int?
  public var patchFingerprint: String?

  public init(
    slug: String, title: String = "", body: String = "", sources: [String] = [],
    materials: [String] = [], citations: [WikiCitation] = [], tags: [String] = [],
    pinned: Bool = false, status: String = "active", revision: Int = 0,
    operation: String = "create", changeNote: String = "", createdAt: String = "",
    updatedAt: String = ""
  ) {
    self.slug = slug
    self.title = title
    self.body = body
    self.sources = sources
    self.materials = materials
    self.citations = citations
    self.tags = tags
    self.pinned = pinned
    self.status = status
    self.revision = revision
    self.operation = operation
    self.changeNote = changeNote
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
  enum CodingKeys: String, CodingKey {
    case slug, title, body, sources, materials, citations, tags, pinned, status, revision,
      operation, changeNote, createdAt, updatedAt, restoredFromRevision, patchFingerprint
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    slug = try c.decodeIfPresent(String.self, forKey: .slug) ?? ""
    title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
    body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
    sources = try c.decodeIfPresent([String].self, forKey: .sources) ?? []
    materials = try c.decodeIfPresent([String].self, forKey: .materials) ?? []
    citations = try c.decodeIfPresent([WikiCitation].self, forKey: .citations) ?? []
    tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    status = try c.decodeIfPresent(String.self, forKey: .status) ?? "active"
    revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
    operation = try c.decodeIfPresent(String.self, forKey: .operation) ?? "create"
    changeNote = try c.decodeIfPresent(String.self, forKey: .changeNote) ?? ""
    createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    restoredFromRevision = try c.decodeIfPresent(Int.self, forKey: .restoredFromRevision)
    patchFingerprint = try c.decodeIfPresent(String.self, forKey: .patchFingerprint)
  }
  public func sameContent(as other: WikiPage) -> Bool {
    title == other.title && body == other.body && sources == other.sources && tags == other.tags
      && materials == other.materials && citations == other.citations
      && pinned == other.pinned && status == other.status
  }
}

public struct WikiAttachment: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var name: String
  public var byteCount: Int
  public var sha256: String
  public var createdAt: String
}

public struct WikiLog: Codable, Identifiable, Sendable {
  public var id: String
  public var action: String
  public var slug: String
  public var revision: Int?
  public var at: String
}

public struct WikiDraft: Codable, Sendable {
  public var page: WikiPage
  public var updatedAt: String
  public init(page: WikiPage) {
    self.page = page
    updatedAt = WikiJSON.now()
  }
}

public enum WikiJSON {
  public static func encoder() -> JSONEncoder {
    let result = JSONEncoder()
    result.keyEncodingStrategy = .convertToSnakeCase
    result.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return result
  }
  public static func decoder() -> JSONDecoder {
    let result = JSONDecoder()
    result.keyDecodingStrategy = .convertFromSnakeCase
    return result
  }
  public static func now() -> String {
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return format.string(from: Date())
  }
  public static func encode<T: Encodable>(_ value: T) throws -> String {
    String(decoding: try encoder().encode(value), as: UTF8.self)
  }
  public static func object<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: encoder().encode(value))
  }
}

public enum WikiValidation {
  public static func slug(_ value: String) throws -> String {
    let value = value.precomposedStringWithCanonicalMapping
    guard
      value.range(of: "^[\\p{L}\\p{N}][\\p{L}\\p{N}_-]{0,95}$", options: .regularExpression) != nil
    else { throw WikiError.invalid("slug") }
    return value
  }
  public static func text(
    _ value: String, field: String, bytes: Int, count: Int? = nil, multiline: Bool = false,
    empty: Bool = false
  ) throws -> String {
    let result =
      multiline
      ? value
      : value.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
    let invalid = result.unicodeScalars.contains { scalar in
      (scalar.value < 32 && !(multiline && [9, 10, 13].contains(scalar.value)))
        || scalar.value == 127
    }
    guard !invalid, result.utf8.count <= bytes, count.map({ result.count <= $0 }) ?? true,
      empty || !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw WikiError.invalid(field) }
    return result
  }
  public static func provenanceURL(_ value: String) throws -> String {
    if value.isEmpty { return value }
    if chatDeepLink(value) != nil { return value }
    guard let url = URLComponents(string: value),
      ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil, url.user == nil,
      url.password == nil, value.utf8.count <= 2048
    else { throw WikiError.invalid("url") }
    return value
  }
  public static func chatDeepLink(_ value: String) -> URL? {
    guard value.utf8.count <= 2048, let url = URLComponents(string: value),
      url.scheme?.lowercased() == "codex", url.host?.lowercased() == "threads",
      url.user == nil, url.password == nil, url.port == nil,
      url.query == nil, url.fragment == nil,
      url.path.hasPrefix("/"), url.percentEncodedPath == url.path,
      UUID(uuidString: String(url.path.dropFirst())) != nil
    else { return nil }
    return url.url
  }
}
