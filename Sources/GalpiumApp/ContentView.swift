import AppKit
import GalpiumCore
import SwiftUI

struct ContentView: View {
  @ObservedObject var model: AppModel
  let delegate: AppDelegate
  @Environment(\.openWindow) private var openWindow
  @State private var sourceSheet = false
  @FocusState private var searching: Bool
  private var searchText: Binding<String> {
    model.section == "materials"
      ? Binding(
        get: { model.materialQuery },
        set: model.changeMaterialSearch) : $model.search
  }
  var body: some View {
    VStack(spacing: 0) {
      if !model.isEditing {
        HStack(spacing: 12) {
          HStack(spacing: 4) {
            Button(action: model.goBack) {
              Image(systemName: "chevron.left").frame(width: 24, height: 24)
            }
            .disabled(!model.canGoBack).help(localized("뒤로"))
            .accessibilityLabel(localized("뒤로")).accessibilityIdentifier("navigation-back")
            Button(action: model.goForward) {
              Image(systemName: "chevron.right").frame(width: 24, height: 24)
            }
            .disabled(!model.canGoForward).help(localized("앞으로"))
            .accessibilityLabel(localized("앞으로")).accessibilityIdentifier("navigation-forward")
          }.buttonStyle(.borderless)
          Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
          TextField(
            model.section == "materials" ? localized("자료에서 검색…") : localized("내 위키에서 검색…"),
            text: searchText
          ).textFieldStyle(.plain).focused(
            $searching
          )
          .accessibilityLabel(
            model.section == "materials" ? localized("자료 검색") : localized("위키 검색")
          )
          .accessibilityIdentifier(model.section == "materials" ? "material-search" : "wiki-search")
          .id(model.section == "materials" ? "material-search-field" : "wiki-search-field")
          if model.section != "materials" && model.searchIsRunning {
            ProgressView().controlSize(.small).help(localized("검색 중"))
          }
          if model.section != "materials" && !model.searchIsRunning
            && model.searchState == "warming"
          {
            Image(systemName: "clock").foregroundStyle(.secondary).help(
              localized("의미 검색 준비 중 · 키워드 결과를 먼저 표시합니다"))
          }
          if model.section != "materials" && !model.searchIsRunning
            && model.searchState == "unavailable"
          {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary).help(
              localized("의미 검색을 사용할 수 없어 키워드로 검색했습니다"))
          }
          if !searchText.wrappedValue.isEmpty {
            Button {
              searchText.wrappedValue = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
            }.buttonStyle(.plain).help(localized("검색 지우기"))
          }
          Button(localized("새 페이지"), systemImage: "plus", action: { model.newPage() }).buttonStyle(
            .borderedProminent)
        }.padding(.horizontal, 24).padding(.vertical, 14)
        Divider()
      }
      if let error = model.error {
        feedback(error, symbol: "exclamationmark.triangle", color: .red) { model.error = nil }
      }
      if let notice = model.notice {
        feedback(notice, symbol: "checkmark.circle", color: Theme.accent) { model.notice = nil }
      }
      HSplitView {
        if !model.isEditing { sidebar.frame(minWidth: 210, idealWidth: 245, maxWidth: 320) }
        Group {
          if model.isEditing {
            editor
          } else if model.section == "materials" {
            MaterialsView(model: model)

          } else if let page = model.currentPage {
            article(page)

          } else {
            home
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.paper).clipShape(
          RoundedRectangle(cornerRadius: 14)
        ).modifier(NavigationSwipeAnimation(presentation: model.swipePresentation))
          .id(model.navigationRenderIdentity).transition(.opacity)
          .padding(model.isEditing ? 14 : 20)
        if !model.inspector.isEmpty {
          inspector.frame(
            minWidth: 280,
            idealWidth: model.inspector == "history" || model.inspector == "conflict" ? 390 : 330,
            maxWidth: 520
          ).background(Theme.paper)
        }
      }
      HStack {
        Spacer()
        if model.isBusy {
          ProgressView().controlSize(.small)
          Text(model.operationName)
          Button(localized("취소"), action: model.cancelOperation)
        }
        Menu {
          SettingsLink { Text(localized("앱 설정…")) }
          Divider()
          Button(localized("AI 연결"), systemImage: "link") { model.inspector = "connection" }
          Button(localized("위키 구조 점검"), systemImage: "checklist") { model.inspector = "lint" }
        } label: {
          Image(systemName: "gearshape").frame(width: 28, height: 24).contentShape(Rectangle())
        }.menuStyle(.borderlessButton).fixedSize().help(localized("설정"))
          .accessibilityLabel(localized("설정")).accessibilityIdentifier("settings-menu")
      }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 9)
    }
    .frame(minWidth: 900, minHeight: 620).background(Theme.field)
    .sheet(isPresented: $sourceSheet) { AddTextMaterialSheet(model: model) }
    .background(NavigationGestures(model: model).frame(width: 0, height: 0))
    .onAppear {
      let action = openWindow
      delegate.reopenMainWindow = { action(id: "main") }
    }
    .environment(
      \.openURL,
      OpenURLAction { url in
        model.openLink(url)
        return .handled
      }
    )
    .background(Button(localized("검색")) { searching = true }.keyboardShortcut("k").hidden())
    .onChange(of: model.search) { _, _ in model.filtersChanged() }
    .onChange(of: model.materialQuery) { _, _ in model.startMaterialSearch() }
    .onChange(of: model.status) { _, _ in model.filtersChanged() }
    .onChange(of: model.tag) { _, _ in model.filtersChanged() }
    .onChange(of: model.section) { _, _ in model.filtersChanged() }
  }
  private func feedback(_ text: String, symbol: String, color: Color, dismiss: @escaping () -> Void)
    -> some View
  {
    HStack(alignment: .top) {
      Image(systemName: symbol)
      Text(text).textSelection(.enabled)
      Spacer()
      Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).help(
        localized("알림 닫기"))
    }.font(.callout).foregroundStyle(color).padding(12).background(color.opacity(0.08))
  }
  private var sidebar: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        VStack(spacing: 6) {
          navButton(
            localized("내 위키"), icon: "house", active: model.sidebarDestination == .wiki,
            id: "sidebar-wiki", action: model.home)
          navButton(
            localized("자료"), icon: "tray.full", active: model.sidebarDestination == .materials,
            id: "sidebar-materials", action: model.showMaterials)
          navButton(
            localized("보관함"), icon: "archivebox", active: model.sidebarDestination == .archive,
            id: "sidebar-archive", action: model.showArchive)

        }
        if model.section != "sources" && model.section != "materials" {
          let pinned = model.filteredPages.filter(\.pinned)
          let recent = model.filteredPages.filter { !$0.pinned }
          if !pinned.isEmpty { pageGroup(localized("고정한 페이지"), pinned) }
          pageGroup(model.search.isEmpty ? localized("최근 페이지") : localized("검색 결과"), recent)
          if model.pages.count < model.pageTotal {
            Button(localized("문서 더 보기"), action: model.morePages)
          }
          VStack(alignment: .leading, spacing: 9) {
            Text(localized("태그")).font(.caption).foregroundStyle(.secondary)
            Button(localized("전체")) { model.tag = nil }.buttonStyle(.plain).foregroundStyle(
              model.tag == nil ? Theme.accent : .secondary)
            ForEach(model.tags, id: \.self) { tag in
              Button {
                model.tag = model.tag == tag ? nil : tag
              } label: {
                HStack {
                  Image(systemName: "number")
                  Text(tag)
                  Spacer()
                }
              }.buttonStyle(.plain).foregroundStyle(model.tag == tag ? Theme.accent : .primary)
            }
          }
        } else if model.section == "sources" {
          VStack(alignment: .leading, spacing: 10) {
            Text(localized("원본 자료")).font(.caption).foregroundStyle(.secondary)
            ForEach(model.filteredSources) { source in
              WikiRowButton(
                selected: model.selectedSource == source.slug,
                action: { model.openSource(source.slug) }
              ) {
                VStack(alignment: .leading, spacing: 4) {
                  Text(source.title).lineLimit(2)
                  Text(shortDate(source.createdAt)).font(.caption).foregroundStyle(.secondary)
                }
              }
            }
          }
          if model.sources.count < model.sourceTotal {
            Button(localized("원본 더 보기"), action: model.moreSources)
          }
        }
      }.padding(18)
    }
  }
  private func navButton(
    _ title: String, icon: String, active: Bool, id: String,
    action: @escaping () -> Void
  ) -> some View {
    WikiRowButton(selected: active, action: action) {
      Label(title, systemImage: icon)
    }.accessibilityIdentifier(id)
  }
  private func pageGroup(_ title: String, _ pages: [PageSummary]) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      if pages.isEmpty {
        Text(localized("표시할 문서가 없습니다.")).font(.callout).foregroundStyle(.secondary).padding(
          .vertical, 8)
      }
      ForEach(pages) { page in
        WikiRowButton(selected: model.selected == page.slug, action: { model.open(page) }) {
          VStack(alignment: .leading, spacing: 5) {
            Text(page.title).lineLimit(2).fontWeight(
              model.selected == page.slug ? .medium : .regular)
            Text(shortDate(page.updatedAt)).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
  }
  private var home: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack {
          Text(model.sidebarDestination == .archive ? localized("보관함") : localized("내 위키"))
            .font(.system(size: 28, weight: .semibold))
          Spacer()
        }
        if model.sidebarDestination == .archive {
          Picker(localized("종류"), selection: $model.archiveKind) {
            Text(localized("문서")).tag("pages")
            Text(localized("자료")).tag("materials")
          }.pickerStyle(.segmented).onChange(of: model.archiveKind) { _, _ in model.showArchive() }
        }
        if !model.drafts.isEmpty { draftRecovery }
        if !model.libraryHasContent && model.sidebarDestination != .archive {
          VStack(alignment: .leading, spacing: 16) {
            Text(localized("첫 페이지를 시작하세요")).font(.title3).fontWeight(.semibold)
            HStack {
              Button(localized("새 페이지"), systemImage: "plus", action: { model.newPage() })
                .buttonStyle(
                  .borderedProminent)
              Button(
                localized("자료 가져오기…"), systemImage: "square.and.arrow.down",
                action: model.importMaterials)
              Button(localized("텍스트 추가…")) { sourceSheet = true }
            }
          }.padding(.vertical, 28)
        } else {
          Text(
            !model.search.isEmpty
              ? localized("검색 결과")
              : model.sidebarDestination == .archive ? localized("보관된 페이지") : localized("최근 문서")
          ).font(.headline)
          ForEach(model.filteredPages) { page in
            WikiRowButton(selected: false, action: { model.open(page) }) {
              VStack(alignment: .leading, spacing: 7) {
                HStack {
                  Text(page.title).font(.system(size: 17, weight: .medium))
                  if page.pinned {
                    Image(systemName: "pin.fill").font(.caption).foregroundStyle(Theme.accent)
                  }
                  Spacer()
                  Text("r\(page.revision)").font(.caption).foregroundStyle(.secondary)
                }
                Text(String(page.excerpt.prefix(140)).replacingOccurrences(of: "\n", with: " "))
                  .lineLimit(2).foregroundStyle(.secondary)
                Divider().padding(.top, 8)
              }.frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          if model.filteredPages.isEmpty {
            Text(localized("조건에 맞는 문서가 없습니다.")).foregroundStyle(.secondary)
          }
        }
      }.padding(28).frame(maxWidth: 840, alignment: .leading).frame(
        maxWidth: .infinity, alignment: .topLeading)
    }
  }
  private var draftRecovery: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(localized("기기에 보관된 초안"), systemImage: "arrow.counterclockwise").font(.headline)
      ForEach(model.drafts, id: \.page.slug) { draft in
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text(draft.page.title.isEmpty ? localized("제목 없는 초안") : draft.page.title)
            Text(localized("기준 r%ld · %@", draft.page.revision, shortDate(draft.updatedAt))).font(
              .caption
            )
            .foregroundStyle(.secondary)
          }
          Spacer()
          Button(localized("복구")) { model.recover(draft) }
          Button(localized("버리기")) { model.discardDraft(draft) }.foregroundStyle(.secondary)
        }
      }
    }.padding(16).background(Theme.accent.opacity(0.08)).clipShape(
      RoundedRectangle(cornerRadius: 10))
  }
  private func article(_ page: WikiPage) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          Text(page.title).font(.system(size: 26, weight: .semibold)).textSelection(.enabled)
          if page.status == "archived" {
            Label(localized("보관됨"), systemImage: "archivebox").font(.caption).foregroundStyle(
              .secondary)
          }
          Spacer()
        }
        Text(localized("수정 %@ · 개정 %ld", shortDate(page.updatedAt), page.revision)).font(.caption)
          .foregroundStyle(.secondary)
        if !page.tags.isEmpty {
          Text(page.tags.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
        }
        HStack {
          if page.status == "active" {
            Button(localized("편집"), systemImage: "pencil", action: model.edit).buttonStyle(
              .borderedProminent)
          } else {
            Button(localized("사용 중으로 복원"), systemImage: "arrow.counterclockwise") {
              model.restore(page.revision)
            }.buttonStyle(.borderedProminent)
          }
          Menu(localized("더 보기")) {
            Button(localized("변경 이력"), action: model.history)
            Button(page.pinned ? localized("고정 해제") : localized("페이지 고정"), action: model.togglePin)
              .disabled(
                page.status == "archived")
            Button(localized("Markdown 내보내기…"), action: model.exportMarkdown)
            Button(localized("링크 복사")) {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString("[[\(page.slug)]]", forType: .string)
            }
            if page.status == "active" {
              Divider()
              Button(localized("문서 보관…"), action: model.archive)
            }
          }.fixedSize()
          Spacer()
          Button(localized("출처와 백링크"), systemImage: "sidebar.right") {
            model.inspector = model.inspector == "references" ? "" : "references"
          }.buttonStyle(.plain).help(localized("출처와 연결된 문서 보기"))
        }
      }.padding(24)
      Divider()
      MarkdownView(
        bodyText: page.body, store: model.store, citations: page.citations, contents: true)
      Divider()
      DisclosureGroup(localized("연결된 자료")) {
        let ids = (try? model.store?.materialIDs(in: page)) ?? []
        ForEach(ids.sorted(), id: \.self) { id in
          if let item = try? model.store?.material(id) {
            Button(item.title) { model.openMaterial(id) }.buttonStyle(.plain).foregroundStyle(
              Theme.accent)
          }
        }
      }.padding(18)

    }
  }
  private var editor: some View {
    GeometryReader { geometry in
      let narrow = geometry.size.width < 820
      let mode = narrow && model.editorMode == "split" ? "write" : model.editorMode
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 14) {
          Button(localized("문서로")) {
            model.navigate { if model.selected == nil { model.section = "home" } }
          }
          TextField(localized("문서 제목"), text: $model.draft.title).font(
            .system(size: 18, weight: .medium)
          )
          .textFieldStyle(.plain).onChange(of: model.draft.title) { _, _ in model.changed() }
          .accessibilityLabel(localized("문서 제목"))
          VStack(alignment: .trailing, spacing: 4) {
            Text(model.saveStatus).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack {
              Button(localized("저장")) { _ = model.save() }.buttonStyle(.borderedProminent)
              Button(localized("완료"), action: model.finish).disabled(model.isBusy)
            }
          }
        }.padding(18)
        Divider()
        HStack(spacing: 8) {
          if mode != "preview" {
            Menu(localized("서식")) {
              ForEach(
                [
                  ("heading", localized("제목")), ("bold", localized("굵게")),
                  ("italic", localized("기울임")), ("list", localized("목록")),
                  ("quote", localized("인용")), ("code", localized("코드")), ("link", localized("링크")),
                  ("table", localized("표")),
                ], id: \.0
              ) { kind, label in Button(label) { model.editor.format(kind) } }
            }.fixedSize()
            Button {
              model.editor.format("bold")
            } label: {
              Image(systemName: "bold")
            }.help(localized("굵게 · ⌘B"))
            Button {
              model.editor.format("italic")
            } label: {
              Image(systemName: "italic")
            }.help(localized("기울임 · ⌘I"))
            Button {
              model.editor.format("link")
            } label: {
              Image(systemName: "link")
            }.help(localized("링크 삽입"))
            Button {
              model.editor.format("table")
            } label: {
              Image(systemName: "tablecells")
            }.help(localized("표 삽입"))
            Button(localized("파일 첨부"), systemImage: "paperclip", action: model.chooseAttachments)
          }
          Spacer()
          Picker(localized("편집 화면"), selection: $model.editorMode) {
            Text(localized("작성")).tag("write")
            if !narrow { Text(localized("나란히")).tag("split") }
            Text(localized("미리보기")).tag("preview")
          }.pickerStyle(.segmented).frame(width: narrow ? 150 : 230)
        }.padding(12)
        Divider()
        HStack(spacing: 0) {
          if mode != "preview" {
            VStack(alignment: .leading, spacing: 8) {
              Text(localized("Markdown 본문")).font(.caption).foregroundStyle(.secondary).padding(
                .horizontal, 18
              ).padding(.top, 12)
              NativeEditor(
                text: $model.draft.body, identity: model.draft.slug, bridge: model.editor,
                onChange: model.changed, onFiles: model.attachFiles, onImage: model.pasteImage,
                onScroll: { model.scrollFraction = $0 }, onOverflow: { model.error = $0 })
            }.frame(minWidth: 280, maxWidth: .infinity)
          }
          if mode == "split" { Divider() }
          if mode != "write" {
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text(localized("실시간 미리보기"))
                Spacer()
                if mode == "split" {
                  Toggle(localized("스크롤 연결"), isOn: $model.scrollSync).toggleStyle(.checkbox)
                }
              }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).padding(
                .top, 12)
              MarkdownView(
                bodyText: model.previewBody, store: model.store, citations: model.draft.citations,
                linksEnabled: false,
                scrollFraction: model.scrollFraction, sync: model.scrollSync && mode == "split")
            }.frame(minWidth: 280, maxWidth: .infinity)
          }
        }
        Divider()
        DisclosureGroup(localized("문서 설정 · 출처, 태그와 변경 요약")) {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text(localized("태그")).frame(width: 60, alignment: .leading)
              TextField(localized("쉼표로 구분"), text: $model.draftTags).onChange(of: model.draftTags) {
                _, _ in
                model.tagsChanged()
              }
              Toggle(localized("페이지 고정"), isOn: $model.draft.pinned).onChange(
                of: model.draft.pinned
              ) {
                _, _ in
                model.changed()
              }
            }
            HStack {
              Text(localized("변경 요약")).frame(width: 60, alignment: .leading)
              TextField(localized("어떤 내용을 바꿨나요?"), text: $model.draft.changeNote).onChange(
                of: model.draft.changeNote
              ) { _, _ in model.changed() }
            }
            TextField(localized("자료 검색"), text: $model.pickerQuery).onChange(of: model.pickerQuery)
            { _, _ in model.pickerQueryChanged() }
            ScrollView {
              LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(model.pickerMaterials) { item in
                  HStack {
                    Toggle(
                      item.title,
                      isOn: Binding(
                        get: { model.draft.materials.contains(item.id) },
                        set: { value in
                          if value {
                            model.draft.materials.append(item.id)
                          } else {
                            model.draft.materials.removeAll { $0 == item.id }
                          }
                          model.changed()
                        })
                    ).toggleStyle(.checkbox)
                    Spacer()
                    MaterialCitationButton(model: model, material: item)
                  }
                }
              }
            }.frame(maxHeight: 140)
          }.padding(.top, 12)
        }.padding(14)
      }
    }
  }
  private var inspector: some View {
    InspectorView(model: model)
  }
}

func shortDate(_ text: String) -> String {
  let input = ISO8601DateFormatter()
  input.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  let fallback = ISO8601DateFormatter()
  guard let date = input.date(from: text) ?? fallback.date(from: text) else { return text }
  return date.formatted(.dateTime.year().month().day().hour().minute().locale(Localization.locale))
}

struct WikiRowButton<LabelContent: View>: View {
  let selected: Bool
  let action: () -> Void
  @ViewBuilder var label: () -> LabelContent
  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      label().frame(maxWidth: .infinity, alignment: .leading).padding(10)
        .foregroundStyle(selected ? Theme.accent : .primary)
        .background {
          RoundedRectangle(cornerRadius: 8)
            .fill(Theme.accent.opacity(selected ? (hovered ? 0.16 : 0.12) : hovered ? 0.06 : 0))
            .animation(.easeOut(duration: 0.14), value: hovered)
        }
        .contentShape(Rectangle())
    }.buttonStyle(.plain).onHover { hovered = $0 }
      .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
