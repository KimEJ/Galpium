import AVKit
import AppKit
import GalpiumCore
import ImageIO
import PDFKit
import SwiftUI

struct MaterialsView: View {
  @ObservedObject var model: AppModel
  @State private var addingText = false
  @State private var viewMode = "preview"
  @State private var renaming: WikiMaterial?
  var body: some View {
    Group {
      if let item = model.openedMaterial {
        detail(item)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            HStack {
              Text(model.status == "archived" ? localized("보관함") : localized("자료")).font(
                .system(size: 28, weight: .semibold))
              Spacer()
              if model.status == "active" {
                Menu(localized("자료 추가")) {
                  Button(localized("파일 가져오기…"), action: model.importMaterials)
                  Button(localized("텍스트 추가…")) { addingText = true }
                }.menuStyle(.borderlessButton).fixedSize()
              }
            }
            if model.status == "archived" {
              Picker(localized("종류"), selection: $model.archiveKind) {
                Text(localized("문서")).tag("pages")
                Text(localized("자료")).tag("materials")
              }.pickerStyle(.segmented).onChange(of: model.archiveKind) { _, _ in
                model.showArchive()
              }
            }
            Picker(localized("종류"), selection: $model.materialKind) {
              Text(localized("전체")).tag("all")
              Text(localized("텍스트")).tag("text")
              Text("PDF").tag("pdf")
              Text(localized("이미지")).tag("image")
              Text(localized("오디오")).tag("audio")
              Text(localized("기타 파일")).tag("file")
            }.pickerStyle(.segmented).onChange(of: model.materialKind) { _, _ in
              model.filtersChanged()
            }
            HStack(spacing: 8) {
              Text(localized("자료 %ld개", model.materials.count))
              if model.materialSearchIsRunning {
                ProgressView().controlSize(.mini).help(localized("검색 중"))
              } else if model.materialSearchState == "warming" {
                Image(systemName: "clock").help(
                  localized("의미 검색 준비 중 · 키워드 결과를 먼저 표시합니다"))
              } else if model.materialSearchState == "partial" {
                Image(systemName: "exclamationmark.circle").help(
                  localized("일부 자료의 의미 검색을 준비하지 못했습니다"))
              } else if model.materialSearchState == "unavailable" {
                Image(systemName: "exclamationmark.circle").help(
                  localized("의미 검색을 사용할 수 없어 키워드로 검색했습니다"))
              }
            }.font(.caption).foregroundStyle(.secondary)
            if model.materials.isEmpty {
              Text(localized("표시할 자료가 없습니다.")).foregroundStyle(.secondary)
            }
            LazyVStack(spacing: 4) {
              ForEach(model.materials) { item in
                HStack {
                  WikiRowButton(selected: false, action: { model.openMaterialSearchResult(item) }) {
                    HStack(spacing: 14) {
                      Image(
                        systemName: item.kind == "image"
                          ? "photo"
                          : item.kind == "pdf"
                            ? "doc.richtext"
                            : item.kind == "audio" ? "waveform" : "doc.text"
                      ).foregroundStyle(.secondary)
                      VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).lineLimit(2)
                        if let match = model.materialSearchMatch(for: item) {
                          MaterialSearchMatchView(match: match)
                            .accessibilityIdentifier("material-match-" + item.id)
                        }
                      }.frame(maxWidth: .infinity, alignment: .leading)
                      if let id = item.fileID, let file = try? model.store?.attachment(id) {
                        Text(
                          ByteCountFormatter.string(
                            fromByteCount: Int64(file.byteCount), countStyle: .file)
                        ).font(.caption).foregroundStyle(.secondary).frame(
                          width: 80, alignment: .trailing)
                      }

                    }.padding(.vertical, 8)
                  }.accessibilityIdentifier("material-" + item.id)
                  MaterialReferenceButton(
                    model: model, item: item, count: model.materialLinkCounts[item.id, default: 0])
                  actions(item)
                }.disabled(model.isBusy)
              }
            }
          }.padding(28).frame(maxWidth: 1000, alignment: .leading).frame(
            maxWidth: .infinity, alignment: .topLeading)
        }
      }
    }.sheet(isPresented: $addingText) { AddTextMaterialSheet(model: model) }
      .sheet(item: $renaming) { MaterialRenameSheet(model: model, item: $0) }
      .dropDestination(for: URL.self) { urls, _ in
        model.importMaterialURLs(urls)
        return !urls.isEmpty
      }
  }
  private func actions(_ item: WikiMaterial) -> some View {
    Menu {
      Button(localized("이름 변경…")) { renaming = item }
      if item.fileID != nil {
        Button(localized("열기")) { model.openMaterialFile(item) }
        Button(localized("Finder에서 보기")) { model.openMaterialFile(item, reveal: true) }
      }
      Button(item.status == "active" ? localized("보관") : localized("복원")) {
        model.archiveMaterial(item)
      }
      Divider()
      Button(localized("삭제…"), role: .destructive) { model.deleteMaterial(item) }
    } label: {
      Image(systemName: "ellipsis").frame(width: 24, height: 24)
    }
    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel(localized("%@ 자료 동작", item.title))
  }
  private func detail(_ item: WikiMaterial) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(item.title).font(.system(size: 26, weight: .semibold)).lineLimit(2)
        Spacer()
        actions(item)
      }
      HStack {
        Button(localized("이 자료로 새 문서")) { model.newPage(material: item) }.buttonStyle(
          .borderedProminent)
        if item.fileID != nil { Button(localized("열기")) { model.openMaterialFile(item) } }
      }
      if !item.url.isEmpty, let url = URL(string: item.url) {
        if WikiValidation.chatDeepLink(item.url) != nil {
          Link(destination: url) {
            Label(localized("ChatGPT에서 열기"), systemImage: "arrow.up.forward.app")
              .foregroundStyle(Theme.accent)
          }.font(.callout).accessibilityIdentifier("material-chat-link")
        } else {
          Link(item.url, destination: url).font(.caption)
        }
      }
      Divider()
      if item.kind == "pdf" {
        Picker(localized("화면"), selection: $viewMode) {
          Text(localized("미리보기")).tag("preview")
          Text(localized("텍스트")).tag("text")
        }.pickerStyle(.segmented)
      }
      if let file = try? model.store?.materialFileURL(item), item.kind == "pdf",
        viewMode == "preview"
      {
        MaterialPDFView(url: file, page: model.materialPage).frame(minHeight: 220)
      } else if let file = try? model.store?.materialFileURL(item), item.kind == "image" {
        MaterialImageView(url: file).frame(maxHeight: 380)
      } else if let file = try? model.store?.materialFileURL(item), item.kind == "audio" {
        MaterialAudioView(url: file, startSeconds: model.materialStartSeconds).frame(height: 80)
      }
      if model.materialTextLoading { ProgressView().controlSize(.small) }
      if let error = model.materialTextError {
        Text(error).font(.caption).foregroundStyle(.secondary)
      }
      if let text = model.materialText, !text.pages.isEmpty,
        item.kind != "pdf" || viewMode == "text"
      {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
              ForEach(text.pages, id: \.number) { page in
                VStack(alignment: .leading, spacing: 10) {
                  if item.kind == "pdf" {
                    Text(localized("%ld쪽", page.number)).font(.caption).foregroundStyle(.secondary)
                  }
                  ForEach(
                    Array(page.text.components(separatedBy: "\n\n").enumerated()), id: \.offset
                  ) { index, paragraph in
                    Text(Markdown.linkedOriginal(paragraph)).tint(Theme.accent).textSelection(
                      .enabled
                    ).frame(
                      maxWidth: .infinity, alignment: .leading
                    )
                    .padding(6).background(
                      !model.materialQuote.isEmpty && paragraph.contains(model.materialQuote)
                        ? Theme.accent.opacity(0.12) : Color.clear
                    )
                    .id("paragraph-\(page.number)-\(index)")
                  }
                }.id(page.number)
              }
            }
          }.onAppear {
            let page = text.pages.first { $0.number == model.materialPage }
            if !model.materialQuote.isEmpty,
              let index = page?.text.components(separatedBy: "\n\n").firstIndex(where: {
                $0.contains(model.materialQuote)
              })
            {
              proxy.scrollTo("paragraph-\(model.materialPage)-\(index)", anchor: .center)
            } else {
              proxy.scrollTo(model.materialPage, anchor: .top)
            }
          }
        }
      } else if !model.materialTextLoading && item.kind == "pdf"
        && model.materialText?.pages.isEmpty != false
      {
        Text(localized("읽을 수 있는 텍스트가 없습니다.")).font(.caption).foregroundStyle(.secondary)
      }
      Divider()
      Text(localized("연결된 문서")).font(.headline)
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(Array(model.materialReferences.enumerated()), id: \.offset) { _, ref in
            HStack {
              Button(ref.title) {
                if ref.kind == "material" {
                  model.openMaterial(ref.id)
                } else {
                  model.perform { if let page = try model.store?.page(ref.id) { model.open(page) } }
                }
              }.buttonStyle(.plain).foregroundStyle(Theme.accent)
              if ref.historical {
                Text(localized("이력에서 사용")).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
      }.frame(maxHeight: 120)
    }.padding(24)
  }
}

struct MaterialSearchMatchView: View {
  let match: SemanticMatch
  private var isVisual: Bool { match.modality == "image" || match.method == "visual" }
  private var isAudio: Bool { match.modality == "audio" || match.method == "audio" }
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if !isVisual && !isAudio && !match.excerpt.isEmpty {
        Text(match.excerpt).lineLimit(2)
      }
      HStack(spacing: 8) {
        if isVisual { Label(localized("이미지 일치"), systemImage: "photo") }
        if isAudio {
          Label(
            Self.timeRange(start: match.startSeconds, end: match.endSeconds),
            systemImage: "waveform"
          )
          .help(localized("오디오 일치"))
        }
        if let page = match.page, page > 0 { Text(localized("%ld쪽", page)) }
      }
    }.font(.caption).foregroundStyle(.secondary)
  }
  nonisolated static func timeRange(start: Double?, end: Double?) -> String {
    let first = timecode(start ?? 0)
    guard let start, let end, start.isFinite, end.isFinite, end > start else { return first }
    return first + "–" + timecode(end)
  }
  nonisolated private static func timecode(_ seconds: Double) -> String {
    let total = seconds.isFinite ? Int(min(max(0, seconds), Double(Int32.max))) : 0
    if total >= 3600 {
      return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}

struct MaterialAudioView: NSViewRepresentable {
  let url: URL
  let startSeconds: Double
  final class Coordinator {
    var url: URL?
    var startSeconds: Double?
  }
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.controlsStyle = .inline
    view.showsFullScreenToggleButton = false
    return view
  }
  func updateNSView(_ view: AVPlayerView, context: Context) {
    if context.coordinator.url != url {
      view.player?.pause()
      view.player = AVPlayer(url: url)
      context.coordinator.url = url
      context.coordinator.startSeconds = nil
    }
    if context.coordinator.startSeconds != startSeconds {
      view.player?.seek(
        to: CMTime(seconds: startSeconds, preferredTimescale: 600),
        toleranceBefore: .zero, toleranceAfter: .zero)
      context.coordinator.startSeconds = startSeconds
    }
  }
  static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
    view.player?.pause()
    view.player = nil
  }
}

struct MaterialPDFView: NSViewRepresentable {
  let url: URL
  let page: Int
  final class Coordinator {
    var url: URL?
    var page = 0
  }
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeNSView(context: Context) -> PDFView {
    let view = PDFView()
    view.autoScales = true
    return view
  }
  func updateNSView(_ view: PDFView, context: Context) {
    guard context.coordinator.url != url || context.coordinator.page != page else { return }
    context.coordinator.url = url
    context.coordinator.page = page
    if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    if let doc = view.document, let target = doc.page(at: max(0, page - 1)) { view.go(to: target) }
  }
}
struct MaterialImageView: View {
  let url: URL
  @State private var image: NSImage?
  var body: some View {
    Group { if let image { Image(nsImage: image).resizable().scaledToFit() } }
      .task(id: url) {
        let data = await Task.detached(priority: .utility) {
          guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let thumb = CGImageSourceCreateThumbnailAtIndex(
              source, 0,
              [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary)
          else { return Optional<Data>.none }
          let rep = NSBitmapImageRep(cgImage: thumb)
          return rep.representation(using: .png, properties: [:])
        }.value
        image = data.flatMap { NSImage(data: $0) }
      }
  }
}
struct MaterialRenameSheet: View {
  @ObservedObject var model: AppModel
  let item: WikiMaterial
  @State private var title: String
  @Environment(\.dismiss) private var dismiss
  init(model: AppModel, item: WikiMaterial) {
    self.model = model
    self.item = item
    _title = State(initialValue: item.title)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(localized("자료 이름 변경")).font(.headline)
      TextField(localized("이름"), text: $title)
      if let error = model.error { Text(error).foregroundStyle(.red).font(.caption) }
      HStack {
        Spacer()
        Button(localized("취소")) { dismiss() }
        Button(localized("이름 변경")) { if model.renameMaterial(item, title: title) { dismiss() } }
          .keyboardShortcut(.defaultAction)
      }
    }.padding(24).frame(width: 420).onAppear { model.isRenamingAttachment = true }.onDisappear {
      model.isRenamingAttachment = false
    }
  }
}
struct AddTextMaterialSheet: View {
  @ObservedObject var model: AppModel
  @State private var title = ""
  @State private var bodyText = ""
  @State private var url = ""
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(localized("텍스트 자료 추가")).font(.title2)
      TextField(localized("제목"), text: $title)
      TextField(localized("출처 URL · 선택"), text: $url)
      TextEditor(text: $bodyText)
      if let error { Text(error).foregroundStyle(.red).font(.caption) }
      HStack {
        Button(localized("취소")) { dismiss() }
        Spacer()
        Button(localized("추가")) {
          do {
            _ = try model.store?.addTextMaterial(title: title, body: bodyText, url: url)
            try model.refresh()
            dismiss()
          } catch { self.error = error.localizedDescription }
        }.buttonStyle(.borderedProminent).disabled(title.isEmpty || bodyText.isEmpty)
      }
    }.padding(24).frame(width: 640, height: 500)
  }
}
struct MaterialCitationButton: View {
  @ObservedObject var model: AppModel
  let material: WikiMaterial
  @State private var presented = false
  var body: some View {
    Button(localized("인용…")) { presented = true }.sheet(isPresented: $presented) {
      MaterialCitationSheet(model: model, item: material)
    }
  }
}
struct MaterialCitationSheet: View {
  @ObservedObject var model: AppModel
  let item: WikiMaterial
  @State private var extraction: MaterialExtraction?
  @State private var page = 1
  @State private var quote = ""
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(item.title).font(.headline)
      if let extraction {
        Picker(localized("위치"), selection: $page) {
          ForEach(extraction.pages, id: \.number) {
            Text(localized("%ld쪽", $0.number)).tag($0.number)
          }
        }
        ScrollView {
          Text(extraction.pages.first { $0.number == page }?.text ?? "").textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }.frame(height: 220)
        TextEditor(text: $quote).frame(height: 90).overlay(alignment: .topLeading) {
          if quote.isEmpty {
            Text(localized("인용할 원문 구절")).foregroundStyle(.secondary).padding(8).allowsHitTesting(
              false)
          }
        }
      } else {
        Text(localized("읽을 수 있는 텍스트가 없습니다."))
      }
      if let error { Text(error).foregroundStyle(.red).font(.caption) }
      HStack {
        Button(localized("취소")) { dismiss() }
        Spacer()
        Button(localized("각주 삽입")) {
          if model.insertCitation(material: item, page: page, quote: quote) {
            dismiss()
          } else {
            error = model.error
          }
        }.buttonStyle(.borderedProminent).disabled(quote.isEmpty)
      }
    }.padding(24).frame(width: 660).task {
      do {
        let store = model.store
        extraction = try await Task.detached { try store?.materialExtraction(item.id) }.value
        page = extraction?.pages.first?.number ?? 1
      } catch { self.error = error.localizedDescription }
    }
  }
}

private struct MaterialReferenceButton: View {
  @ObservedObject var model: AppModel
  let item: WikiMaterial
  let count: Int
  @State private var presented = false
  var body: some View {
    Button(localized("링크 %ld개", count)) {
      model.perform {
        _ = try model.store?.materialReferences(item.id)
        presented = true
      }
    }.buttonStyle(.plain).font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(
      width: 90, alignment: .trailing
    )
    .popover(isPresented: $presented) {
      let references = (try? model.store?.materialReferences(item.id)) ?? []
      VStack(alignment: .leading, spacing: 12) {
        Text(localized("연결된 문서")).font(.headline)
        if references.isEmpty { Text(localized("아직 연결된 문서가 없습니다.")) }
        ForEach(Array(references.enumerated()), id: \.offset) { _, ref in
          Button(ref.title + (ref.historical ? " · " + localized("이력에서 사용") : "")) {
            presented = false
            if ref.kind == "material" {
              model.openMaterial(ref.id)
            } else {
              model.perform { if let page = try model.store?.page(ref.id) { model.open(page) } }
            }
          }.buttonStyle(.plain).foregroundStyle(Theme.accent)
        }
      }.padding(18).frame(minWidth: 280, maxWidth: 420)
    }
  }
}
