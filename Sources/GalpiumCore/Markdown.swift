import Foundation

public struct MarkdownBlock: Identifiable {
  public var id: Int
  public var kind: String
  public var text: String = ""
  public var level: Int = 0
  public var rows: [[String]] = []
}
public struct MarkdownToken {
  public var kind: String
  public var text: String = ""
  public var href: String?
  public var children: [MarkdownToken] = []
}

public struct MarkdownFootnote: Identifiable, Sendable {
  public var id: String
  public var text: String
}

public enum Markdown {
  private static func groups(_ pattern: String, _ text: String) -> [String]? {
    guard
      let match = try? NSRegularExpression(pattern: pattern).firstMatch(
        in: text, range: NSRange(text.startIndex..., in: text))
    else { return nil }
    return (0..<match.numberOfRanges).map {
      Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? ""
    }
  }
  public static func blocks(_ body: String) -> [MarkdownBlock] {
    let lines = body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(
      of: "\r", with: "\n"
    ).components(separatedBy: "\n")
    var result = [MarkdownBlock]()
    var i = 0
    func append(_ kind: String, _ text: String = "", level: Int = 0, rows: [[String]] = []) {
      result.append(
        MarkdownBlock(id: result.count, kind: kind, text: text, level: level, rows: rows))
    }
    func tableStart(_ index: Int) -> Bool {
      index + 1 < lines.count && lines[index].contains("|")
        && groups(
          "^\\|?\\s*:?-{3,}:?\\s*(?:\\|\\s*:?-{3,}:?\\s*)+\\|?$",
          lines[index + 1].trimmingCharacters(in: .whitespaces)) != nil
    }
    func startsBlock(_ line: String) -> Bool {
      groups("^(?:#{1,6}\\s|`{3,}|~{3,}|>\\s?|[-*+]\\s|\\d+\\.\\s|(?:---+|\\*\\*\\*+)\\s*$)", line)
        != nil
    }
    while i < lines.count {
      let line = lines[i]
      if line.trimmingCharacters(in: .whitespaces).isEmpty {
        i += 1
        continue
      }
      if let fence = groups("^(`{3,}|~{3,})(.*)$", line) {
        var code = [String]()
        i += 1
        while i < lines.count && !lines[i].hasPrefix(fence[1]) {
          code.append(lines[i])
          i += 1
        }
        if i < lines.count { i += 1 }
        append("code", code.joined(separator: "\n"))
        continue
      }
      if let note = groups("^\\[\\^([\\p{L}\\p{N}_-]+)\\]:\\s*(.*)$", line) {
        var text = [note[2]]
        i += 1
        while i < lines.count && (lines[i].hasPrefix("    ") || lines[i].hasPrefix("\t")) {
          text.append(
            lines[i].hasPrefix("\t") ? String(lines[i].dropFirst()) : String(lines[i].dropFirst(4)))
          i += 1
        }
        append("footnote", text.joined(separator: "\n"), rows: [[note[1]]])
        continue
      }
      if let heading = groups("^(#{1,6})\\s+(.+)$", line) {
        append("heading", heading[2], level: heading[1].count)
        i += 1
        continue
      }
      if groups("^(?:---+|\\*\\*\\*+)\\s*$", line) != nil {
        append("rule")
        i += 1
        continue
      }
      if tableStart(i) {
        var rows = [cells(line)]
        i += 2
        while i < lines.count && !lines[i].isEmpty && lines[i].contains("|") {
          rows.append(cells(lines[i]))
          i += 1
        }
        append("table", rows: rows)
        continue
      }
      if line.hasPrefix(">") {
        var quotes = [String]()
        while i < lines.count && lines[i].hasPrefix(">") {
          quotes.append(String(lines[i].dropFirst()).trimmingCharacters(in: .whitespaces))
          i += 1
        }
        append("quote", quotes.joined(separator: "\n"))
        continue
      }
      if let list = groups("^([-*+]|\\d+\\.)\\s+(.+)$", line) {
        let ordered = list[1].first?.isNumber == true
        var rows = [[String]]()
        while i < lines.count, let row = groups("^([-*+]|\\d+\\.)\\s+(.+)$", lines[i]),
          (row[1].first?.isNumber == true) == ordered
        {
          rows.append([row[2]])
          i += 1
        }
        append(ordered ? "ordered" : "list", rows: rows)
        continue
      }
      var text = [line]
      i += 1
      while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty
        && !startsBlock(lines[i]) && !tableStart(i) && !lines[i].hasPrefix("[^")
      {
        text.append(lines[i])
        i += 1
      }
      append("paragraph", text.joined(separator: "\n"))
    }
    return result
  }
  public static func cells(_ line: String) -> [String] {
    let line = line.trimmingCharacters(in: .whitespaces)
    let pattern =
      "\\[\\[[^\\]]+\\]\\]|!?\\[[^\\]]+\\]\\([^\\s)]+\\)|`[^`]+`|\\\\.|\\||[^|\\\\\\[\\x60!]+|."
    var cell = ""
    var cells = [String]()
    if let regex = try? NSRegularExpression(pattern: pattern) {
      for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
        let part = (line as NSString).substring(with: match.range)
        if part == "|" {
          cells.append(cell.trimmingCharacters(in: .whitespaces))
          cell = ""
        } else {
          cell += part.replacingOccurrences(of: "\\|", with: "|")
        }
      }
    }
    cells.append(cell.trimmingCharacters(in: .whitespaces))
    if line.hasPrefix("|") { cells.removeFirst() }
    if line.hasSuffix("|") && cells.last == "" { cells.removeLast() }
    return cells
  }
  public static func safeLink(_ value: String) -> String? {
    if WikiValidation.chatDeepLink(value) != nil { return value }
    if value.hasPrefix("attachment:") {
      let id = String(value.dropFirst(11))
      return id.range(of: "^[a-f0-9]{32}$", options: .regularExpression) == nil
        ? nil : "galpium://attachment/" + id
    }
    for (prefix, kind) in [("source:", "source"), ("wiki:", "page"), ("material:", "material")]
    where value.hasPrefix(prefix) {
      let slug = String(value.dropFirst(prefix.count))
      guard (try? WikiValidation.slug(slug)) != nil else { return nil }
      return "galpium://\(kind)/"
        + (slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug)
    }
    guard let url = URLComponents(string: value),
      ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? ""), url.user == nil,
      url.password == nil
    else { return nil }
    if url.scheme != "mailto" && url.host == nil { return nil }
    return value
  }
  public static func linkedOriginal(_ value: String) -> AttributedString {
    var result = AttributedString(value)
    let range = NSRange(value.startIndex..., in: value)
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    let chatLinks = try? NSRegularExpression(
      pattern: "codex://[^\\s<>\\[\\]()\"'`]+", options: .caseInsensitive)
    let matches =
      (detector?.matches(in: value, range: range) ?? [])
      + (chatLinks?.matches(in: value, range: range) ?? [])
    for match in matches {
      guard let textRange = Range(match.range, in: value) else { continue }
      let original = String(value[textRange])
      let trimmed = original.trimmingCharacters(in: CharacterSet(charactersIn: ".,;。）」』"))
      let candidate = WikiValidation.chatDeepLink(trimmed) != nil ? trimmed : original
      guard let safe = safeLink(candidate), let url = URL(string: safe) else { continue }
      let end = value.index(textRange.lowerBound, offsetBy: candidate.count)
      guard let attributedRange = Range(textRange.lowerBound..<end, in: result) else { continue }
      result[attributedRange].link = url
    }
    return result
  }
  public static func inline(_ value: String, depth: Int = 0) -> [MarkdownToken] {
    if depth > 3 { return [MarkdownToken(kind: "text", text: value)] }
    let pattern =
      "\\[\\[([^\\]|]+)(?:\\|([^\\]]+))?\\]\\]|(!?)\\[([^\\]]+)\\]\\(([^\\s)]+)\\)|`([^`]+)`|\\*\\*([^*]+)\\*\\*|~~([^~]+)~~|\\*([^*]+)\\*|\\[\\^([\\p{L}\\p{N}_-]+)\\]|\\n"
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return [MarkdownToken(kind: "text", text: value)]
    }
    let ns = value as NSString
    var offset = 0
    var tokens = [MarkdownToken]()
    for match in regex.matches(in: value, range: NSRange(location: 0, length: ns.length)) {
      func group(_ index: Int) -> String {
        let range = match.range(at: index)
        return range.location == NSNotFound ? "" : ns.substring(with: range)
      }
      if match.range.location > offset {
        tokens.append(
          MarkdownToken(
            kind: "text",
            text: ns.substring(
              with: NSRange(location: offset, length: match.range.location - offset))))
      }
      if !group(1).isEmpty {
        let slug = group(1).components(separatedBy: "#")[0]
        tokens.append(
          MarkdownToken(
            kind: "link", text: group(2).isEmpty ? slug : group(2), href: safeLink("wiki:" + slug)))
      } else if !group(4).isEmpty {
        let image = !group(3).isEmpty && group(5).hasPrefix("attachment:")
        tokens.append(
          MarkdownToken(
            kind: image ? "image" : "link",
            text: !group(3).isEmpty && !image ? localized("이미지: %@", group(4)) : group(4),
            href: safeLink(group(5))))
      } else if !group(6).isEmpty {
        tokens.append(MarkdownToken(kind: "code", text: group(6)))
      } else if !group(7).isEmpty || !group(8).isEmpty || !group(9).isEmpty {
        let type = !group(7).isEmpty ? "bold" : !group(8).isEmpty ? "strike" : "italic"
        let text = !group(7).isEmpty ? group(7) : !group(8).isEmpty ? group(8) : group(9)
        tokens.append(MarkdownToken(kind: type, children: inline(text, depth: depth + 1)))
      } else if !group(10).isEmpty {
        tokens.append(MarkdownToken(kind: "footnote", text: group(10)))
      } else {
        tokens.append(MarkdownToken(kind: "text", text: "\n"))
      }
      offset = match.range.location + match.range.length
    }
    if offset < ns.length {
      tokens.append(MarkdownToken(kind: "text", text: ns.substring(from: offset)))
    }
    return tokens
  }
  private static func links(_ body: String, host: String) -> [String] {
    var targets = Set<String>()
    func visit(_ tokens: [MarkdownToken]) {
      for token in tokens {
        if let href = token.href, let url = URL(string: href), url.scheme == "galpium",
          url.host == host
        {
          targets.insert(
            String(url.path.dropFirst()).removingPercentEncoding ?? String(url.path.dropFirst()))
        }
        visit(token.children)
      }
    }
    for block in blocks(body) where block.kind != "code" {
      visit(inline(block.text))
      for row in block.rows { for cell in row { visit(inline(cell)) } }
    }
    return targets.sorted()
  }
  public static func footnotes(_ body: String) -> [MarkdownFootnote] {
    blocks(body).filter { $0.kind == "footnote" }.map {
      MarkdownFootnote(id: $0.rows[0][0], text: $0.text)
    }
  }
  public static func footnoteReferences(_ text: String) -> [String] {
    var result = [String]()
    let regex = try! NSRegularExpression(pattern: "`[^`]*`|\\[\\^([\\p{L}\\p{N}_-]+)\\]")
    let ns = text as NSString
    for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
    where m.range(at: 1).location != NSNotFound {
      let id = ns.substring(with: m.range(at: 1))
      if !result.contains(id) { result.append(id) }
    }
    return result
  }
  public static func materialIDs(_ body: String) -> [String] { links(body, host: "material") }
  public static func sourceIDs(_ body: String) -> [String] { links(body, host: "source") }
  public static func wikiLinks(_ body: String) -> [String] { links(body, host: "page") }
  public static func attachmentIDs(_ body: String) -> [String] { links(body, host: "attachment") }
}

public struct TextReplacement: Codable, Equatable {
  public var oldText: String
  public var newText: String
  public init(_ old: String, _ new: String) {
    oldText = old
    newText = new
  }
}
public struct DiffLine: Codable, Identifiable {
  public var id: Int
  public var type: String
  public var text: String
  public var oldLine: Int?
  public var newLine: Int?
}
public struct LineDiff: Codable {
  public var rows: [DiffLine]
  public var added: Int
  public var removed: Int
  public var coarse: Bool
}
public enum TextTools {
  public static func replace(_ body: String, replacements: [TextReplacement]) throws -> String {
    let ns = body as NSString
    let edits = try replacements.map { item -> (NSRange, String) in
      guard !item.oldText.isEmpty else { throw WikiError.invalid("old_text") }
      _ = try WikiValidation.text(
        item.oldText, field: "old_text", bytes: 64 * 1024, multiline: true, empty: true)
      _ = try WikiValidation.text(
        item.newText, field: "new_text", bytes: 64 * 1024, multiline: true, empty: true)
      let range = ns.range(of: item.oldText)
      guard range.location != NSNotFound else { throw WikiError.invalid("patch text not found") }
      let next = ns.range(
        of: item.oldText,
        range: NSRange(location: range.location + 1, length: ns.length - range.location - 1))
      guard next.location == NSNotFound else { throw WikiError.invalid("ambiguous patch") }
      return (range, item.newText)
    }.sorted { $0.0.location < $1.0.location }
    var end = 0
    var result = ""
    for (range, replacement) in edits {
      guard range.location >= end else { throw WikiError.invalid("overlapping patch") }
      result +=
        ns.substring(with: NSRange(location: end, length: range.location - end)) + replacement
      end = NSMaxRange(range)
    }
    return result + ns.substring(from: end)
  }
  public static func diff(_ before: String, _ after: String, context: Int = 3) -> LineDiff {
    let a = before.components(separatedBy: "\n")
    let b = after.components(separatedBy: "\n")
    var prefix = 0
    var suffix = 0
    while prefix < min(a.count, b.count) && a[prefix] == b[prefix] { prefix += 1 }
    while suffix < min(a.count - prefix, b.count - prefix)
      && a[a.count - suffix - 1] == b[b.count - suffix - 1]
    { suffix += 1 }
    let left = Array(a[prefix..<(a.count - suffix)])
    let right = Array(b[prefix..<(b.count - suffix)])
    var rows = [DiffLine]()
    var old = 1
    var new = 1
    func add(_ type: String, _ line: String) {
      rows.append(
        DiffLine(
          id: rows.count, type: type, text: line, oldLine: type == "add" ? nil : old,
          newLine: type == "remove" ? nil : new))
      if type != "add" { old += 1 }
      if type != "remove" { new += 1 }
    }
    for line in a.prefix(prefix) { add("context", line) }
    // Bounded LCS: at most 250,000 cells, then explicit replacement blocks.
    let width = right.count + 1
    let coarse = (left.count + 1) * width > 250_000
    if coarse {
      for line in left { add("remove", line) }
      for line in right { add("add", line) }
    } else {
      var lcs = [Int32](repeating: 0, count: (left.count + 1) * width)
      if !left.isEmpty && !right.isEmpty {
        for i in stride(from: left.count - 1, through: 0, by: -1) {
          for j in stride(from: right.count - 1, through: 0, by: -1) {
            lcs[i * width + j] =
              left[i] == right[j]
              ? 1 + lcs[(i + 1) * width + j + 1]
              : max(lcs[(i + 1) * width + j], lcs[i * width + j + 1])
          }
        }
      }
      var i = 0
      var j = 0
      while i < left.count || j < right.count {
        if i < left.count && j < right.count && left[i] == right[j] {
          add("context", left[i])
          i += 1
          j += 1
        } else if i < left.count
          && (j == right.count || lcs[(i + 1) * width + j] >= lcs[i * width + j + 1])
        {
          add("remove", left[i])
          i += 1
        } else {
          add("add", right[j])
          j += 1
        }
      }
    }
    for line in a.suffix(suffix) { add("context", line) }
    var keep = Set<Int>()
    let context = min(10, max(0, context))
    for (index, row) in rows.enumerated() where row.type != "context" {
      for item in max(0, index - context)...min(rows.count - 1, index + context) {
        keep.insert(item)
      }
    }
    return LineDiff(
      rows: rows.filter { keep.contains($0.id) }, added: rows.filter { $0.type == "add" }.count,
      removed: rows.filter { $0.type == "remove" }.count, coarse: coarse)
  }
}
