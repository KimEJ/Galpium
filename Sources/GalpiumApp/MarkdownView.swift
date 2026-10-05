import AppKit
import GalpiumCore
import SwiftUI

enum Theme {
  static let accent = Color(
    nsColor: NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 0.45, green: 0.79, blue: 0.68, alpha: 1)
        : NSColor(red: 0.055, green: 0.43, blue: 0.36, alpha: 1)
    })
  static let paper = Color(nsColor: .textBackgroundColor)
  static let field = Color(nsColor: .windowBackgroundColor)
  static let layer = Color(nsColor: .controlBackgroundColor)
}

struct MarkdownView: View {
  @Environment(\.openURL) private var inheritedOpenURL
  let bodyText: String
  let store: WikiStore?
  var citations = [WikiCitation]()
  @State private var selectedFootnote: MarkdownFootnote?
  var linksEnabled = true
  var scrollFraction: CGFloat = 0
  var sync = false
  var contents = false

  var body: some View {
    let blocks = Markdown.blocks(bodyText)
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if contents && blocks.contains(where: { $0.kind == "heading" }) {
            DisclosureGroup(localized("목차")) {
              VStack(alignment: .leading, spacing: 8) {
                ForEach(blocks.filter { $0.kind == "heading" }) { block in
                  Button(block.text) { proxy.scrollTo(block.id, anchor: .top) }.buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
              }.padding(.top, 8)
            }.font(.callout).padding(.bottom, 12)
          }
          ForEach(blocks.filter { $0.kind != "footnote" }) { block in blockView(block).id(block.id)
          }
          if !orderedFootnotes.isEmpty {
            Divider()
            ForEach(Array(orderedFootnotes.enumerated()), id: \.element.id) { index, note in
              HStack(alignment: .top, spacing: 10) {
                Button("[\(index + 1)]") { selectedFootnote = note }.buttonStyle(.plain)
                  .foregroundStyle(Theme.accent)
                Text(attributed(note.text.replacingOccurrences(of: "\n> ", with: "\n"))).font(
                  .caption
                ).textSelection(.enabled)
                Button {
                  if let block = blocks.first(where: {
                    $0.kind != "footnote" && $0.kind != "code"
                      && Markdown.footnoteReferences($0.text).contains(note.id)
                  }) {
                    proxy.scrollTo(block.id, anchor: .center)
                  }
                } label: {
                  Image(systemName: "arrow.uturn.backward")
                }.buttonStyle(.plain).help(localized("본문으로 돌아가기"))
              }.id("note-" + note.id)
            }
          }
        }
        .frame(maxWidth: 790, alignment: .leading).padding(24).frame(
          maxWidth: .infinity, alignment: .topLeading
        )
        .background(
          PreviewScrollFollower(fraction: scrollFraction, enabled: sync).frame(width: 0, height: 0))
      }.textSelection(.enabled)
    }
    .popover(item: $selectedFootnote) { note in
      VStack(alignment: .leading, spacing: 12) {
        Text(
          attributed(
            citations.contains { $0.id == note.id }
              ? String(note.text.split(separator: "\n").first ?? "") : note.text)
        ).textSelection(.enabled)
        if let citation = citations.first(where: { $0.id == note.id }) {
          Text(citation.quote).textSelection(.enabled).font(.callout)
          Button(localized("원문 보기")) {
            var target = URLComponents()
            target.scheme = "galpium"
            target.host = "citation"
            target.path = "/" + citation.materialID
            target.queryItems = [
              URLQueryItem(name: "page", value: String(citation.page)),
              URLQueryItem(name: "extraction", value: citation.extractionID),
              URLQueryItem(name: "quote", value: citation.quote),
            ]
            if let url = target.url { inheritedOpenURL(url) }
            selectedFootnote = nil
          }
        }
      }.padding(18).frame(width: 380)
    }
    .environment(
      \.openURL,
      OpenURLAction { url in
        if url.scheme == "galpium", url.host == "footnote" {
          selectedFootnote = orderedFootnotes.first { $0.id == String(url.path.dropFirst()) }
        } else if linksEnabled {
          inheritedOpenURL(url)
        }
        return .handled
      })
  }
  private var orderedFootnotes: [MarkdownFootnote] {
    let blocks = Markdown.blocks(bodyText)
    var ids = [String]()
    for block in blocks where block.kind != "code" && block.kind != "footnote" {
      for id in Markdown.footnoteReferences(
        ([block.text] + block.rows.flatMap { $0 }).joined(separator: "\n")) where !ids.contains(id)
      { ids.append(id) }
    }
    let notes = Markdown.footnotes(bodyText)
    return ids.compactMap { id in notes.first { $0.id == id } }
  }
  @ViewBuilder private func blockView(_ block: MarkdownBlock) -> some View {
    switch block.kind {
    case "heading":
      Text(attributed(block.text)).font(
        .system(size: block.level == 1 ? 28 : block.level == 2 ? 22 : 18, weight: .semibold)
      ).padding(.top, 12).accessibilityAddTraits(.isHeader)
    case "rule": Divider().padding(.vertical, 6)
    case "code":
      ScrollView(.horizontal) {
        Text(block.text).font(.system(size: 13, design: .monospaced)).frame(
          maxWidth: .infinity, alignment: .leading
        ).padding(14)
      }.background(Theme.layer).clipShape(RoundedRectangle(cornerRadius: 8))
    case "quote":
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "quote.opening").foregroundStyle(.secondary)
        inlineView(block.text)
      }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Theme.layer)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    case "list", "ordered":
      VStack(alignment: .leading, spacing: 9) {
        ForEach(Array(block.rows.enumerated()), id: \.offset) { index, row in
          HStack(alignment: .top, spacing: 10) {
            Text(block.kind == "ordered" ? "\(index + 1)." : "•").foregroundStyle(.secondary)
            inlineView(row[0])
          }
        }
      }
    case "table":
      ScrollView(.horizontal) {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
          ForEach(Array(block.rows.enumerated()), id: \.offset) { index, row in
            GridRow {
              ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                Text(attributed(cell)).fontWeight(index == 0 ? .semibold : .regular).padding(
                  .horizontal, 12
                ).padding(.vertical, 10).frame(minWidth: 110, alignment: .leading).background(
                  index == 0 ? Theme.layer : Color.clear)
              }
            }
            Divider().gridCellColumns(block.rows.first?.count ?? 1)
          }
        }
      }.accessibilityLabel(localized("문서 표"))
    default: inlineView(block.text)
    }
  }
  @ViewBuilder private func inlineView(_ text: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(attributed(text)).font(.system(size: 15)).lineSpacing(7).fixedSize(
        horizontal: false, vertical: true
      ).frame(maxWidth: .infinity, alignment: .leading)
      ForEach(
        Array(Markdown.inline(text).enumerated()).filter { $0.element.kind == "image" },
        id: \.offset
      ) { _, token in
        if let href = token.href, let url = URL(string: href),
          let attachment = try? store?.attachment(String(url.path.dropFirst())),
          let file = store?.attachmentURL(attachment), let image = NSImage(contentsOf: file)
        {
          Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 380).accessibilityLabel(
            token.text)
        } else {
          Label(localized("%@ · 첨부 이미지를 찾을 수 없습니다", token.text), systemImage: "photo").font(
            .callout
          )
          .foregroundStyle(.secondary)
        }
      }
    }
  }
  private func attributed(_ text: String) -> AttributedString {
    func render(_ tokens: [MarkdownToken]) -> AttributedString {
      var result = AttributedString()
      for token in tokens {
        var part = token.children.isEmpty ? AttributedString(token.text) : render(token.children)
        switch token.kind {
        case "bold": part.inlinePresentationIntent = .stronglyEmphasized
        case "italic": part.inlinePresentationIntent = .emphasized
        case "strike": part.strikethroughStyle = .single
        case "code":
          part.font = .system(size: 13, design: .monospaced)
          part.backgroundColor = Theme.layer
        case "footnote":
          let number =
            orderedFootnotes.firstIndex { $0.id == token.text }.map { String($0 + 1) } ?? "?"
          part = AttributedString("[" + number + "]")
          part.font = .system(size: 11)
          part.baselineOffset = 5
          part.link = URL(string: "galpium://footnote/" + token.text)
        case "link", "image":
          if let href = token.href, let url = URL(string: href) {
            part.link = url
            part.foregroundColor = Theme.accent
            part.underlineStyle = .single
          }
        default: break
        }
        result += part
      }
      return result
    }
    return render(Markdown.inline(text))
  }
}
