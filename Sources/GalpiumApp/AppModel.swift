import AppKit
import Combine
import GalpiumCore
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
  @Published var pages = [PageSummary]()
  @Published var sources = [SourceSummary]()
  @Published var tagNames = [String]()
  @Published var pageTotal = 0
  @Published var sourceTotal = 0
  @Published var pickerSources = [SourceSummary]()
  @Published var selectedPickerSources = [SourceSummary]()
  @Published var pickerQuery = ""
  @Published var pickerTotal = 0
  @Published var citationTitles = [String: String]()
  private var pickerLimit = 100
  @Published var libraryHasContent = false
  @Published private var openedPage: WikiPage?
  @Published private var openedSource: WikiSource?
  private var pageLimit = 100
  private var sourceLimit = 100
  @Published var drafts = [WikiDraft]()
  @Published var selected: String?
  @Published var selectedSource: String?
  @Published var section = "home"
  @Published var search = ""
  @Published var searchIsRunning = false
  @Published var searchState = ""
  private var searchTask: Task<Void, Never>?
  private var searchGeneration = 0
  private var semanticCoverage = -1
  private var semanticState = ""
  private var semanticRetryAt = Date.distantPast
  @Published var status = "active"
  @Published var tag: String?
  @Published var isEditing = false
  @Published var draft = WikiPage(slug: "new")
  @Published var draftTags = ""
  @Published var baseline: WikiPage?
  @Published var saveStatus = ""
  @Published var error: String?
  @Published var notice: String? {
    didSet {
      noticeDismissal?.cancel()
      noticeDismissal = nil
      guard notice != nil else { return }
      noticeDismissal = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(4)) } catch { return }
        guard !Task.isCancelled else { return }
        self?.notice = nil
      }
    }
  }
  @Published var inspector = ""
  @Published var attachments = [WikiAttachment]()
  @Published var attachmentLinkCounts = [String: Int]()
  @Published var materialQuery = ""
  var attachmentQuery: String {
    get { materialQuery }
    set { materialQuery = newValue }
  }
  @Published var materials = [WikiMaterial]()
  @Published var materialSearchMatches = [String: SemanticMatch]()
  @Published var materialSearchState = ""
  @Published var materialSearchIsRunning = false
  @Published var materialKind = "all"
  @Published var archiveKind = "pages"
  @Published var selectedMaterial: String?
  @Published var openedMaterial: WikiMaterial?
  @Published var materialText: MaterialExtraction?
  @Published var materialTextLoading = false
  @Published var materialTextError: String?
  @Published var materialPage = 1
  @Published var materialStartSeconds: Double = 0
  @Published var materialQuote = ""
  @Published var materialExtractionID: String?
  @Published var materialReferences = [MaterialReference]()
  @Published var materialLinkCounts = [String: Int]()
  @Published var pickerMaterials = [WikiMaterial]()
  private var materialTask: Task<Void, Never>?
  private var materialSearchTask: Task<Void, Never>?
  @Published var isRenamingAttachment = false
  @Published private(set) var backLocations = [NavigationLocation]()
  @Published private(set) var forwardLocations = [NavigationLocation]()
  @Published private(set) var navigationRenderIdentity = 0
  @Published var revisions = [WikiPage]()
  @Published var historyRevision: Int?
  @Published var historyTotal = 0
  private var historyLimit = 100
  @Published var conflict: WikiPage?
  @Published var isBusy = false
  @Published var operationName = ""
  @Published var previewBody = ""
  @Published var editorMode = "split"
  @Published var scrollSync = true
  @Published var scrollFraction: CGFloat = 0
  let editor = EditorBridge()
  let swipePresentation = NavigationSwipePresentation()
  let connections = MCPConnectionStatus()
  private(set) var store: WikiStore?
  private var timer: Timer?
  private var draftWork: DispatchWorkItem?
  private var previewWork: DispatchWorkItem?
  private var token = ""
  private var operationTask: Task<Void, Never>?
  private var noticeDismissal: Task<Void, Never>?

  init(root: URL = WikiStore.defaultRoot) {
    do {
      store = try WikiStore(root: root)
      try refresh()
      connections.refresh(root: store?.root)
    } catch { self.error = error.localizedDescription }
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.connections.refresh(root: self.store?.root)
        guard !self.isBusy, let store = self.store else {
          return
        }
        let state = store.semanticStatus()
        let coverage = state.indexedPages + state.indexedMaterials
        if store.changeToken != self.token || coverage != self.semanticCoverage
          || state.state != self.semanticState
        {
          self.perform { try self.refresh() }
        } else if state.state == "partial", Date().timeIntervalSince(self.semanticRetryAt) >= 60 {
          self.semanticRetryAt = Date()
          store.scheduleSemanticIndex()
        }
      }
    }
  }
  var currentPage: WikiPage? { openedPage?.slug == selected ? openedPage : nil }
  var currentSource: WikiSource? { openedSource?.slug == selectedSource ? openedSource : nil }
  var dirty: Bool {
    isEditing
      && (baseline == nil
        ? !draft.title.isEmpty || !draft.body.isEmpty
        : !draft.sameContent(as: baseline!) || draft.changeNote != baseline!.changeNote)
  }
  var filteredPages: [PageSummary] { pages }
  var filteredSources: [SourceSummary] { sources }
  var tags: [String] { tagNames }
  var filteredAttachments: [WikiAttachment] {
    let query = attachmentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    return attachments.filter { query.isEmpty || $0.name.localizedStandardContains(query) }
  }
  func filtersChanged() {
    pageLimit = 100
    sourceLimit = 100
    perform { try refresh() }
  }
  func morePages() {
    pageLimit += 100
    perform { try refresh() }
  }
  func moreSources() {
    sourceLimit += 100
    perform { try refresh() }
  }
  func refresh() throws {
    guard let store else { return }
    connections.refresh(root: store.root)
    pages = try store.pageSummaries(status: status, tag: tag, query: search, limit: pageLimit)
    sources = try store.sourceSummaries(
      query: section == "sources" ? search : "", limit: sourceLimit)
    pageTotal = try store.pageCount(status: status, tag: tag, query: search)
    sourceTotal = try store.sourceCount(query: section == "sources" ? search : "")
    libraryHasContent = try store.pageCount(status: "all") > 0
    tagNames = try store.tags(status: status)
    if let selected { openedPage = try store.page(selected) }
    if let selectedSource { openedSource = try store.source(selectedSource) }
    try loadCitationTitles()
    if isEditing { try loadSourcePicker() }
    drafts = try store.drafts()
    attachments = try store.attachments().sorted {
      $0.createdAt > $1.createdAt || ($0.createdAt == $1.createdAt && $0.name < $1.name)
    }
    if section == "files" { attachmentLinkCounts = try store.attachmentLinkCounts() }
    if section == "materials" {
      materials = try store.materials(status: status, kind: materialKind)
      materialLinkCounts = try store.materialLinkCounts()
      if let selectedMaterial {
        openedMaterial = try store.material(selectedMaterial)
        materialReferences = try store.materialReferences(selectedMaterial)
      }
      startMaterialSearch()
    }
    if isEditing { pickerMaterials = try store.materials(query: pickerQuery) }
    token = store.changeToken
    let semantic = store.semanticStatus()
    semanticCoverage = semantic.indexedPages + semantic.indexedMaterials
    semanticState = semantic.state
    if semantic.state == "partial" { semanticRetryAt = Date() }
    store.scheduleSemanticIndex()
    startHybridSearch()
    if isEditing, let latest = try? store.page(draft.slug), latest.revision != draft.revision {
      saveStatus = localized("외부 변경 있음 · r%ld과 비교 필요", latest.revision)
    }
    if inspector == "history", let slug = selected {
      revisions = try store.history(slug, limit: historyLimit)
      historyTotal = try store.historyCount(slug)
    }
  }
  private func startHybridSearch() {
    searchTask?.cancel()
    searchGeneration += 1
    let generation = searchGeneration
    guard let store, section != "sources", section != "files", section != "materials",
      !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      searchIsRunning = false
      searchState = ""
      return
    }
    let query = search
    let status = self.status
    let tag = self.tag
    let limit = pageLimit
    searchIsRunning = true
    searchTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(250))
        let result = try await Task.detached(priority: .userInitiated) {
          try store.hybridSearch(
            query: query, status: status, tag: tag, limit: min(limit, 10000), offset: 0)
        }.value
        guard let self, !Task.isCancelled, generation == self.searchGeneration else { return }
        self.pages = result.items
        self.pageTotal = result.total
        self.searchState = result.status.state
        self.searchIsRunning = false
      } catch {
        guard let self, !Task.isCancelled, generation == self.searchGeneration else { return }
        self.searchState = "unavailable"
        self.searchIsRunning = false
      }
    }
  }
  func perform(_ block: () throws -> Void) {
    do { try block() } catch { self.error = error.localizedDescription }
  }
  @discardableResult
  func navigate(recordHistory: Bool = true, _ action: () -> Void) -> Bool {
    guard !isRenamingAttachment else { return false }
    guard !isBusy else {
      notice = localized("%@을 마치거나 취소한 뒤 이동하세요.", operationName)
      return false
    }
    if dirty {
      let alert = NSAlert()
      alert.messageText = localized("변경한 문서를 저장할까요?")
      alert.informativeText = localized("저장하지 않고 이동하면 이 편집 내용은 버려집니다.")
      alert.addButton(withTitle: localized("저장하고 이동"))
      alert.addButton(withTitle: localized("변경 버리기"))
      alert.addButton(withTitle: localized("계속 편집"))
      switch alert.runModal() {
      case .alertFirstButtonReturn: guard save() else { return false }
      case .alertSecondButtonReturn: perform { try store?.deleteDraft(draft.slug) }
      default: return false
      }
    }
    let previous = navigationLocation
    draftWork?.cancel()
    previewWork?.cancel()
    isEditing = false
    conflict = nil
    inspector = ""
    selectedMaterial = nil
    openedMaterial = nil
    materialText = nil
    materialTask?.cancel()
    error = nil
    action()
    if recordHistory, previous != navigationLocation {
      backLocations.append(previous)
      if backLocations.count > 50 { backLocations.removeFirst() }
      forwardLocations.removeAll()
    }
    return true
  }
  struct NavigationLocation: Equatable {
    var section: String
    var status: String
    var search: String
    var attachmentQuery: String
    var tag: String?
    var page: String?
    var source: String?
    var material: String?
    var materialKind: String
    var archiveKind: String
    var materialPage: Int
    var materialStartSeconds: Double
    var materialQuote: String
    var materialExtractionID: String?
  }
  var navigationLocation: NavigationLocation {
    NavigationLocation(
      section: section, status: status, search: search, attachmentQuery: attachmentQuery, tag: tag,
      page: selected,
      source: selectedSource, material: selectedMaterial, materialKind: materialKind,
      archiveKind: archiveKind, materialPage: materialPage,
      materialStartSeconds: materialStartSeconds, materialQuote: materialQuote,
      materialExtractionID: materialExtractionID)
  }
  var canGoBack: Bool { !isBusy && !isEditing && !isRenamingAttachment && !backLocations.isEmpty }
  var canGoForward: Bool {
    !isBusy && !isEditing && !isRenamingAttachment && !forwardLocations.isEmpty
  }
  func goBack() { moveHistory(backward: true) }
  func goForward() { moveHistory(backward: false) }
  private func moveHistory(backward: Bool) {
    guard backward ? canGoBack : canGoForward,
      let location = backward ? backLocations.last : forwardLocations.last, let store
    else { return }
    perform {
      // Resolve fresh data before changing routes, including pages changed through MCP.
      let page = try location.page.map { try store.page($0) }
      let source = try location.source.map { try store.source($0) }
      let previous = navigationLocation
      guard
        navigate(
          recordHistory: false,
          {
            section = location.section
            status = location.status
            search = location.search
            attachmentQuery = location.attachmentQuery
            tag = location.tag
            selected = location.page
            selectedSource = location.source
            selectedMaterial = location.material
            materialKind = location.materialKind
            archiveKind = location.archiveKind
            materialPage = location.materialPage
            materialStartSeconds = location.materialStartSeconds
            materialQuote = location.materialQuote
            materialExtractionID = location.materialExtractionID
            openedPage = page
            openedSource = source
          })
      else { return }
      if backward {
        backLocations.removeLast()
        forwardLocations.append(previous)
      } else {
        forwardLocations.removeLast()
        backLocations.append(previous)
      }
      try refresh()
      if selectedMaterial != nil { loadMaterialText() }
      navigationRenderIdentity += 1
    }
  }
  enum SidebarDestination { case wiki, sources, archive, attachments, materials }
  var sidebarDestination: SidebarDestination {
    if section == "materials" { return status == "archived" ? .archive : .materials }
    if section == "sources" { return .sources }
    if section == "files" { return .attachments }
    return status == "archived" ? .archive : .wiki
  }
  func showArchive() {
    navigate {
      section = archiveKind == "materials" ? "materials" : "pages"
      status = "archived"
      selected = nil
      selectedSource = nil
      tag = nil
    }
  }
  func home() {
    navigate {
      section = "home"
      status = "active"
      tag = nil
      selected = nil
      selectedSource = nil
    }
  }
  func showSources() { showMaterials() }
  func showAttachments() { showMaterials() }
  func open(_ page: WikiPage) {
    navigate {
      section = "pages"
      selected = page.slug
      selectedSource = nil
      openedPage = page
      perform { try loadCitationTitles() }
    }
  }
  func open(_ summary: PageSummary) {
    perform { if let page = try store?.page(summary.slug) { open(page) } }
  }
  func openSource(_ slug: String) {
    perform { if let item = try store?.materialForSource(slug) { openMaterial(item.id) } }
  }
  func newPage(source: WikiSource? = nil) {
    // Creation retains a fresh identity; reopening a library never replaces existing data.
    navigate {
      draft = WikiPage(
        slug: "page-" + String(UUID().uuidString.prefix(12)).lowercased(),
        title: source?.title ?? "",
        body: source.map {
          ($0.body.utf8.count < 63 * 1024 ? $0.body : localized("## 정리\n\n원본을 읽고 필요한 내용을 작성하세요."))
            + "\n\n[\(localized("원본"))](source:\($0.slug))"
        } ?? "",
        sources: source.map { [$0.slug] } ?? [])
      draftTags = ""
      baseline = nil
      selected = nil
      selectedSource = nil
      section = "pages"
      isEditing = true
      previewBody = draft.body
      saveStatus = localized("새 문서 · 저장 전")
      editorMode = "split"
      pickerQuery = ""
      pickerLimit = 100
      perform { try loadSourcePicker() }
    }
  }
  func chooseLibrary() {
    guard navigate({}) else { return }
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.prompt = localized("이 저장소 사용")
    panel.message = localized("Galpium 저장소 폴더를 선택하거나 새 빈 폴더를 만드세요.")
    guard panel.runModal() == .OK, let root = panel.url else { return }
    perform {
      let replacement = try WikiStore(root: root)
      _ = try replacement.pageSummaries()
      _ = try replacement.sourceSummaries()
      _ = try replacement.drafts()
      store = replacement
      backLocations.removeAll()
      forwardLocations.removeAll()
      attachmentQuery = ""
      selectedMaterial = nil
      selected = nil
      selectedSource = nil
      openedPage = nil
      openedSource = nil
      section = "home"
      search = ""
      tag = nil
      status = "active"
      pageLimit = 100
      sourceLimit = 100
      try refresh()
      try WikiStore.rememberLibrary(root)
      notice = localized("저장소를 열었습니다. 기존 저장소의 데이터는 그대로 보관되어 있습니다.")
    }
  }
  func edit() {
    guard let page = currentPage else { return }
    draft = page
    draft.changeNote = ""
    draftTags = draft.tags.joined(separator: ", ")
    baseline = draft
    isEditing = true
    conflict = nil
    inspector = ""
    previewBody = draft.body
    saveStatus = localized("저장된 문서 · r%ld", page.revision)
    editorMode = "split"
    pickerQuery = ""
    pickerLimit = 100
    perform { try loadSourcePicker() }
  }
  func changed() {
    guard isEditing else { return }
    saveStatus = localized("수정됨 · 문서 저장 전")
    draftWork?.cancel()
    if !dirty {
      perform {
        try store?.deleteDraft(draft.slug)
        drafts = try store?.drafts() ?? []
      }
      saveStatus = localized("문서와 일치 · r%ld", draft.revision)
    }
    let work = DispatchWorkItem { [weak self] in self?.flushDraft() }
    draftWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    if previewWork == nil {
      let preview = DispatchWorkItem { [weak self] in
        guard let self else { return }
        self.previewBody = self.draft.body
        self.previewWork = nil
      }
      previewWork = preview
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: preview)
    }
  }
  func tagsChanged() {
    draft.tags = draftTags.components(separatedBy: ",").map {
      $0.trimmingCharacters(in: .whitespaces)
    }.filter { !$0.isEmpty }
    changed()
  }
  @discardableResult
  func flushDraft() -> Bool {
    draftWork?.cancel()
    guard dirty else { return true }
    guard let store else { return false }
    do {
      try store.saveDraft(WikiDraft(page: draft))
      drafts = try store.drafts()
      saveStatus = localized("기기에 초안 보관됨 · 문서 저장 전")
      return true
    } catch {
      self.error = error.localizedDescription
      saveStatus = localized("초안 보관 실패 · 문서를 저장하세요")
      return false
    }
  }
  @discardableResult
  func save() -> Bool {
    guard let store, isEditing else { return false }
    guard !isBusy else {
      saveStatus = localized("%@ 완료 후 저장하세요", operationName)
      return false
    }
    if editor.textView?.hasMarkedText() == true {
      saveStatus = localized("문자 입력을 마친 뒤 저장하세요")
      return false
    }
    do {
      let page = try store.upsert(draft, expectedRevision: draft.revision, preserveOriginal: false)
      try store.deleteDraft(draft.slug)
      draftWork?.cancel()
      draft = page
      draft.changeNote = ""
      baseline = draft
      selected = page.slug
      saveStatus = localized("문서에 저장됨 · r%ld", page.revision)
      conflict = nil
      error = nil
      try refresh()
      return true
    } catch WikiError.conflict {
      conflict = try? store.page(draft.slug)
      inspector = "conflict"
      flushDraft()
      saveStatus = localized("저장 충돌 · 최신본과 비교하세요")
      return false
    } catch {
      self.error = error.localizedDescription
      flushDraft()
      return false
    }
  }
  func finish() {
    guard !isBusy else {
      saveStatus = localized("%@ 완료 후 문서로 돌아갈 수 있습니다", operationName)
      return
    }
    if !dirty || save() {
      perform {
        try store?.deleteDraft(draft.slug)
        drafts = try store?.drafts() ?? []
      }
      isEditing = false
      inspector = ""
      previewWork?.cancel()
      previewWork = nil
    }
  }
  private func loadCitationTitles() throws {
    let slugs = Set((openedPage?.sources ?? []) + (isEditing ? draft.sources : []))
    citationTitles = Dictionary(
      uniqueKeysWithValues: try store?.selectedSourceSummaries(Array(slugs)).map {
        ($0.slug, $0.title)
      } ?? [])
  }
  private func loadSourcePicker() throws {
    guard let store else { return }
    pickerSources = try store.sourceSummaries(query: pickerQuery, limit: pickerLimit)
    selectedPickerSources = try store.selectedSourceSummaries(draft.sources)
    pickerTotal = try store.sourceCount(query: pickerQuery)
    pickerMaterials = try store.materials(query: pickerQuery)
    try loadCitationTitles()
  }
  func pickerQueryChanged() {
    pickerLimit = 100
    perform { try loadSourcePicker() }
  }
  func morePickerSources() {
    pickerLimit += 100
    perform { try loadSourcePicker() }
  }
  func sourceSelectionChanged() {
    changed()
    perform { try loadSourcePicker() }
  }
  private func insertAttachmentMarkdown(_ text: String) {
    if editor.textView?.window != nil {
      editor.insert(text)
    } else {
      let body = draft.body as NSString
      let range = editor.textView?.selectedRange()
      if let range, editor.textView?.string == draft.body, range.location != NSNotFound,
        NSMaxRange(range) <= body.length
      {
        draft.body = body.replacingCharacters(in: range, with: text)
      } else {
        draft.body += "\n" + text
      }
      changed()
    }
  }
  func testMCPConnection() {
    let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/galpium-mcp")
    let root = store?.root ?? WikiStore.defaultRoot
    runBackground(
      localized("MCP 연결 확인"),
      operation: {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = ["--library", root.path]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: deadline)
        defer {
          deadline.cancel()
          if process.isRunning { process.terminate() }
        }
        let requests: [[String: Any]] = [
          [
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": [
              "protocolVersion": "2025-11-25", "capabilities": [:],
              "clientInfo": ["name": "Galpium connection check", "version": "0.0.1"],
            ],
          ],
          ["jsonrpc": "2.0", "id": 2, "method": "tools/list"],
        ]
        for request in requests {
          var data = try JSONSerialization.data(withJSONObject: request)
          data.append(10)
          try input.fileHandleForWriting.write(contentsOf: data)
        }
        try input.fileHandleForWriting.close()
        let responses = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
          throw WikiError.storage(
            String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }
        let lines = responses.split(separator: 10)
        guard lines.count == 2,
          let result = try JSONSerialization.jsonObject(with: Data(lines[1])) as? [String: Any],
          let payload = result["result"] as? [String: Any],
          let tools = payload["tools"] as? [[String: Any]],
          Set(tools.compactMap { $0["name"] as? String })
            == Set(MCPServer.tools.compactMap { $0["name"] as? String })
        else { throw WikiError.invalid(localized("MCP 초기화 또는 도구 목록")) }
        return tools.count
      },
      completion: { [weak self] (count: Int) in
        self?.notice = localized("MCP 실행·초기화·%ld개 도구 목록을 확인했습니다.", count)
      }
    )
  }
  func recover(_ value: WikiDraft) {
    navigate {
      draft = value.page
      draftTags = draft.tags.joined(separator: ", ")
      baseline = try? store?.page(value.page.slug, revision: value.page.revision)
      isEditing = true
      section = "pages"
      selected = value.page.revision == 0 ? nil : value.page.slug
      previewBody = draft.body
      saveStatus = localized("기기 초안 복구됨 · 문서 저장 전")
      pickerQuery = ""
      pickerLimit = 100
      perform { try loadSourcePicker() }
      if let latest = try? store?.page(draft.slug), latest.revision != draft.revision {
        conflict = latest
        inspector = "conflict"
      }
    }
  }
  func discardDraft(_ value: WikiDraft) {
    perform {
      try store?.deleteDraft(value.page.slug)
      try refresh()
    }
  }
  func reconcileConflict() {
    guard let conflict else { return }
    draft.revision = conflict.revision
    self.conflict = nil
    inspector = ""
    _ = save()
  }
  func history() {
    guard let slug = selected else { return }
    perform {
      historyLimit = 100
      revisions = try store?.history(slug, limit: historyLimit) ?? []
      historyTotal = try store?.historyCount(slug) ?? 0
      historyRevision = revisions.dropFirst().first?.revision ?? revisions.first?.revision
      inspector = "history"
    }
  }
  func moreHistory() {
    historyLimit += 100
    perform { try refresh() }
  }
  func restore(_ revision: Int) {
    guard let current = currentPage, let store else { return }
    let alert = NSAlert()
    alert.messageText = localized("r%ld으로 복원할까요?", revision)
    alert.informativeText = localized("현재 문서와 이력은 보존하고 새 개정을 만듭니다.")
    alert.addButton(withTitle: localized("복원"))
    alert.addButton(withTitle: localized("취소"))
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    perform {
      _ = try store.restore(current.slug, revision: revision, expectedRevision: current.revision)
      try refresh()
      notice = localized("새 개정으로 복원했습니다.")
    }
  }
  func archive() {
    guard let current = currentPage, let store else { return }
    let alert = NSAlert()
    alert.messageText = localized("이 문서를 보관할까요?")
    alert.informativeText = localized("원본·첨부·변경 이력은 유지됩니다. 보관함에서 다시 복원할 수 있습니다.")
    alert.addButton(withTitle: localized("보관"))
    alert.addButton(withTitle: localized("취소"))
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    perform {
      _ = try store.archive(current.slug, expectedRevision: current.revision)
      try refresh()
      notice = localized("문서를 보관했습니다.")
    }
  }
  func togglePin() {
    guard var current = currentPage, let store else { return }
    current.pinned.toggle()
    perform {
      _ = try store.upsert(current, expectedRevision: current.revision)
      try refresh()
    }
  }
  func attachFiles(_ urls: [URL]) {
    guard isEditing, let store else { return }
    runBackground(
      localized("파일 첨부"),
      operation: {
        var attachments = [WikiAttachment]()
        for url in urls {
          try Task.checkCancellation()
          let info = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
          guard info.isRegularFile == true, (info.fileSize ?? Int.max) <= 150 * 1024 * 1024 else {
            throw WikiError.invalid(localized("첨부 가능한 파일은 최대 150 MiB입니다"))
          }
          let item = try store.attach(
            data: Data(contentsOf: url, options: .mappedIfSafe), name: url.lastPathComponent)
          attachments.append(item)
        }
        return attachments
      },
      completion: { [weak self] attachments in
        for item in attachments {
          let isImage = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"].contains(
            URL(fileURLWithPath: item.name).pathExtension.lowercased())
          self?.insertAttachmentMarkdown(
            "\(isImage ? "!" : "")[\(item.name.replacingOccurrences(of: "]", with: "］"))](attachment:\(item.id))\n"
          )
        }
      })
  }
  func pasteImage(_ data: Data) {
    guard let store else { return }
    perform {
      let item = try store.attach(data: data, name: localized("붙여넣은 이미지.png"))
      editor.insert("![\(localized("붙여넣은 이미지"))](attachment:\(item.id))\n")
    }
  }
  func chooseAttachments() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    if panel.runModal() == .OK { attachFiles(panel.urls) }
  }
  func renameAttachment(_ item: WikiAttachment, name: String) -> Bool {
    guard let store, !isBusy else { return false }
    do {
      _ = try store.renameAttachment(item.id, name: name)
      attachmentQuery = ""
      error = nil
      try refresh()
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }
  func exportMarkdown() {
    guard let page = currentPage else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
    panel.nameFieldStringValue = page.slug + ".md"
    if panel.runModal() == .OK, let url = panel.url {
      perform {
        try Data(page.body.utf8).write(to: url, options: .atomic)
        notice = localized("Markdown 문서를 내보냈습니다.")
      }
    }
  }
  func backup() {
    guard let store else { return }
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.prompt = localized("여기에 백업")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let name = "Galpium-" + WikiJSON.now().replacingOccurrences(of: ":", with: "-")
    runBackground(
      localized("전체 백업"), operation: { try store.backup(to: url.appendingPathComponent(name)) },
      completion: { [weak self] in self?.notice = localized("원본·전체 이력·첨부파일 백업을 만들었습니다.") })
  }
  func importBackup() {
    guard let store else { return }
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.prompt = localized("백업 가져오기")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    runBackground(
      localized("백업 가져오기"), operation: { try store.importBackup(from: url) },
      completion: { [weak self] result in
        self?.notice = localized("원본 %ld개, 문서 %ld개와 첨부파일을 가져왔습니다.", result.sources, result.pages)
      })
  }
  private func runBackground<T: Sendable>(
    _ name: String, operation: @escaping @Sendable () throws -> T,
    completion: @escaping @MainActor (T) -> Void
  ) {
    guard !isBusy else { return }
    isBusy = true
    operationName = name
    operationTask = Task {
      let worker = Task.detached(priority: .userInitiated, operation: operation)
      do {
        let result = try await withTaskCancellationHandler(
          operation: { try await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation()
        isBusy = false
        completion(result)
        try refresh()
      } catch is CancellationError {
        notice = localized("%@을 취소했습니다. 이미 보관된 원본 파일은 유지됩니다.", name)
      } catch {
        self.error = error.localizedDescription
      }
      isBusy = false
      operationName = ""
      operationTask = nil
    }
  }
  func cancelOperation() { operationTask?.cancel() }
  func openLink(_ url: URL) {
    guard url.scheme == "galpium" else {
      if Markdown.safeLink(url.absoluteString) != nil, !NSWorkspace.shared.open(url) {
        error = localized("링크를 열 수 없습니다. 연결된 앱을 확인하세요.")
      }
      return
    }
    let slug = String(url.path.dropFirst()).removingPercentEncoding ?? String(url.path.dropFirst())
    switch url.host {
    case "page":
      perform {
        guard let value = try store?.page(slug) else { return }
        open(value)
      }
    case "source": openSource(slug)
    case "material": openMaterial(slug)
    case "citation":
      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      let page = query.first { $0.name == "page" }?.value.flatMap(Int.init) ?? 1
      openMaterial(
        slug, page: page, extractionID: query.first { $0.name == "extraction" }?.value,
        quote: query.first { $0.name == "quote" }?.value ?? "")
    case "attachment":
      perform {
        guard let value = try store?.attachment(slug), let store else { return }
        NSWorkspace.shared.open(store.attachmentURL(value))
      }
    default: break
    }
  }
  var mcpCommand: String {
    let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/galpium-mcp").path
    return
      "[mcp_servers.galpium]\ncommand = \"\(executable.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"\nargs = [\"--library\", \"\((store?.root.path ?? WikiStore.defaultRoot.path).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"]"
  }
}

extension AppModel {
  func changeMaterialSearch(_ value: String) {
    guard value != materialQuery else { return }
    if selectedMaterial != nil { navigate {} }
    materialQuery = value
  }
  func showMaterials() {
    navigate {
      section = "materials"
      status = "active"
      selected = nil
      selectedSource = nil
    }
  }
  func materialSearchMatch(for item: WikiMaterial) -> SemanticMatch? {
    guard !materialQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let match = materialSearchMatches[item.id], match.revision == item.revision
    else { return nil }
    return match
  }
  func openMaterialSearchResult(_ item: WikiMaterial) {
    guard let store else { return }
    perform {
      let current = try store.material(item.id)
      let match = materialSearchMatch(for: current)
      let isText =
        match?.modality != "image" && match?.modality != "audio"
        && match?.method != "visual" && match?.method != "audio"
      openMaterial(
        item.id, page: match?.page ?? 1, quote: isText ? match?.excerpt ?? "" : "",
        startSeconds: match?.startSeconds ?? 0)
    }
  }
  func openMaterial(
    _ id: String, page: Int = 1, extractionID: String? = nil, quote: String = "",
    startSeconds: Double = 0
  ) {
    guard let store else { return }
    perform {
      let item = try store.material(id)
      if navigate({
        section = "materials"
        status = item.status
        selected = nil
        selectedSource = nil
        selectedMaterial = id
        openedMaterial = item
        materialPage = max(1, page)
        materialStartSeconds = startSeconds.isFinite ? max(0, startSeconds) : 0
        materialQuote = quote
        materialExtractionID = extractionID
      }) {
        materialReferences = try store.materialReferences(id)
        loadMaterialText()
      }
    }
  }
  func loadMaterialText() {
    guard let store, let id = selectedMaterial else { return }
    materialTask?.cancel()
    materialText = nil
    materialTextError = nil
    materialTextLoading = true
    let snapshotID = materialExtractionID
    materialTask = Task { [weak self] in
      do {
        let result = try await Task.detached(priority: .userInitiated) {
          if let snapshotID {
            let value = try store.extraction(snapshotID)
            guard value.materialID == id else { throw WikiError.invalid("extraction owner") }
            return value as MaterialExtraction?
          }
          return try store.materialExtraction(id)
        }.value
        guard let self, !Task.isCancelled, self.selectedMaterial == id else { return }
        self.materialText = result
        self.materialTextLoading = false
      } catch {
        guard let self, !Task.isCancelled, self.selectedMaterial == id else { return }
        self.materialTextLoading = false
        self.materialTextError = error.localizedDescription
      }
    }
  }
  func startMaterialSearch() {
    materialSearchTask?.cancel()
    materialSearchMatches = [:]
    materialSearchState = ""
    materialSearchIsRunning = false
    guard let store else { return }
    guard !materialQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      perform { materials = try store.materials(status: status, kind: materialKind) }
      return
    }
    let query = materialQuery
    let status = status
    let kind = materialKind
    materialSearchIsRunning = true
    materialSearchTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(200))
        let result = try await Task.detached(priority: .userInitiated) {
          try store.searchMaterials(query: query, status: status, kind: kind)
        }.value
        guard let self, !Task.isCancelled, self.section == "materials", self.materialQuery == query,
          self.status == status, self.materialKind == kind
        else { return }
        self.materials = result.items
        self.materialSearchMatches = result.matches
        self.materialSearchState = result.state
        self.materialSearchIsRunning = false
      } catch {
        guard let self, !Task.isCancelled, self.section == "materials", self.materialQuery == query,
          self.status == status, self.materialKind == kind
        else { return }
        self.materialSearchState = "unavailable"
        self.materialSearchIsRunning = false
        self.error = error.localizedDescription
      }
    }
  }
  func importMaterials() {
    guard store != nil else { return }
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK else { return }
    importMaterialURLs(panel.urls)
  }
  func importMaterialURLs(_ urls: [URL]) {
    guard let store, !urls.isEmpty else { return }
    runBackground(
      localized("자료 가져오기"),
      operation: {
        for url in urls {
          try Task.checkCancellation()
          let info = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
          guard info.isRegularFile == true, (info.fileSize ?? Int.max) <= 150 * 1024 * 1024 else {
            throw WikiError.invalid("file (150 MiB)")
          }
          _ = try store.importMaterial(
            data: Data(contentsOf: url, options: .mappedIfSafe), name: url.lastPathComponent)
        }
      }, completion: { [weak self] in self?.showMaterials() })
  }
  func newPage(material: WikiMaterial) {
    newPage()
    guard isEditing else { return }
    draft.title = material.title
    draft.materials = [material.id]
  }
  func renameMaterial(_ item: WikiMaterial, title: String) -> Bool {
    guard let store else { return false }
    do {
      _ = try store.updateMaterial(item.id, title: title, expectedRevision: item.revision)
      try refresh()
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }
  func archiveMaterial(_ item: WikiMaterial) {
    perform {
      _ = try store?.updateMaterial(
        item.id, status: item.status == "active" ? "archived" : "active",
        expectedRevision: item.revision)
      selectedMaterial = nil
      openedMaterial = nil
      try refresh()
    }
  }
  func deleteMaterial(_ item: WikiMaterial) {
    guard let store, !isBusy else { return }
    let alert = NSAlert()
    alert.messageText = localized("자료 ‘%@’을 삭제할까요?", item.title)
    alert.addButton(withTitle: localized("삭제"))
    alert.addButton(withTitle: localized("취소"))
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    runBackground(
      localized("자료 삭제"),
      operation: { try store.deleteMaterial(item.id, expectedRevision: item.revision) },
      completion: { [weak self] in
        self?.selectedMaterial = nil
        self?.openedMaterial = nil
      })
  }
  func openMaterialFile(_ item: WikiMaterial, reveal: Bool = false) {
    perform {
      if let url = try store?.materialFileURL(item) {
        if reveal {
          NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
          NSWorkspace.shared.open(url)
        }
      }
    }
  }
  func insertCitation(material: WikiMaterial, page: Int, quote: String) -> Bool {
    guard let store, isEditing else { return false }
    do {
      let existing = draft.citations.first {
        $0.materialID == material.id && $0.page == page && $0.quote == quote
      }
      let citation =
        try existing
        ?? store.makeCitation(
          materialID: material.id, page: page, quote: quote,
          id: "ref-" + String(UUID().uuidString.prefix(8)).lowercased())
      let reference = "[^\(citation.id)]"
      let note =
        existing == nil
        ? "\n\n[^\(citation.id)]: [\(material.title.replacingOccurrences(of: "]",with: "］"))](material:\(material.id)) · \(localized("%ld쪽",page))\n    > \(quote.replacingOccurrences(of: "\n",with: "\n    > "))\n"
        : ""
      let before = editor.textView?.string ?? draft.body
      let range =
        editor.textView?.selectedRange()
        ?? NSRange(location: (before as NSString).length, length: 0)
      let after = (before as NSString).replacingCharacters(in: range, with: reference) + note
      guard after.utf8.count <= 64 * 1024 else { throw WikiError.invalid("body (64 KiB)") }
      guard editor.textView?.hasMarkedText() != true else {
        throw WikiError.invalid("text composition")
      }
      if existing == nil { draft.citations.append(citation) }
      if let view = editor.textView {
        view.undoManager?.beginUndoGrouping()
        editor.insert(reference)
        if !note.isEmpty { editor.insertAtEnd(note) }
        view.undoManager?.endUndoGrouping()
      } else {
        draft.body = after
        changed()
      }
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }
}
