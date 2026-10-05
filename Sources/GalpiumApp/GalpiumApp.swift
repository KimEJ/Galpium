import AppKit
import GalpiumCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  weak var model: AppModel? {
    didSet {
      guard let model, model !== oldValue else { return }
      connectionMenuBar?.remove()
      connectionMenuBar = MenuBarConnectionStatus(model: model, delegate: self)
    }
  }
  private(set) var connectionMenuBar: MenuBarConnectionStatus?
  var reopenMainWindow: (() -> Void)?
  func showMainWindow() {
    reopenMainWindow?()
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showMainWindow()
    return true
  }
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let model else { return .terminateNow }
    if model.isBusy {
      let alert = NSAlert()
      alert.messageText = localized("%@ 작업이 진행 중입니다.", model.operationName)
      alert.informativeText = localized("작업을 마치거나 취소한 뒤 종료할 수 있습니다.")
      alert.addButton(withTitle: localized("계속 작업"))
      alert.addButton(withTitle: localized("작업 취소"))
      if alert.runModal() == .alertSecondButtonReturn { model.cancelOperation() }
      return .terminateCancel
    }
    guard model.dirty else { return .terminateNow }
    let draftPreserved = model.flushDraft()
    let alert = NSAlert()
    alert.messageText = localized("편집 중인 문서를 저장할까요?")
    alert.informativeText = localized("기기 초안은 다음 실행에서 복구할 수 있습니다.")
    alert.addButton(withTitle: localized("저장하고 종료"))
    alert.addButton(withTitle: localized("초안 보관하고 종료"))
    alert.addButton(withTitle: localized("계속 편집"))
    switch alert.runModal() {
    case .alertFirstButtonReturn: return model.save() ? .terminateNow : .terminateCancel
    case .alertSecondButtonReturn: return draftPreserved ? .terminateNow : .terminateCancel
    default: return .terminateCancel
    }
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationWillTerminate(_ notification: Notification) { connectionMenuBar?.remove() }
}

@main
struct GalpiumApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @StateObject private var model = AppModel()
  @AppStorage("appearance") var appearance = "system"
  @AppStorage(Localization.preferenceKey, store: Localization.preferences) private var language =
    "system"
  private var languageSelection: Binding<String> {
    Binding(
      get: { language },
      set: { value in
        language = value
        model.objectWillChange.send()
        model.connections.objectWillChange.send()
        delegate.connectionMenuBar?.update()
      })
  }
  var body: some Scene {
    Window(localized("Galpium"), id: "main") {
      ContentView(model: model, delegate: delegate).tint(Theme.accent)
        .environment(\.locale, Localization.locale)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .onAppear { delegate.model = model }
    }.defaultSize(width: 1240, height: 830).windowResizability(.contentMinSize)
      .commands {
        CommandGroup(replacing: .newItem) {
          Button(localized("새 페이지"), action: { model.newPage() }).keyboardShortcut("n")
          Button(localized("자료 가져오기…"), action: model.importMaterials).keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
          Button(localized("저장"), action: { _ = model.save() }).keyboardShortcut("s").disabled(
            !model.isEditing)
          Button(localized("Markdown 내보내기…"), action: model.exportMarkdown).disabled(
            model.currentPage == nil)
        }
        CommandMenu(localized("위키")) {
          Button(localized("뒤로"), action: model.goBack).keyboardShortcut("[").disabled(
            !model.canGoBack)
          Button(localized("앞으로"), action: model.goForward).keyboardShortcut("]").disabled(
            !model.canGoForward)
          Divider()
          Button(localized("내 위키 홈"), action: model.home).keyboardShortcut(
            "h", modifiers: [.command, .shift])
          Button(localized("자료"), action: model.showMaterials)
          Button(localized("문서 편집"), action: model.edit).keyboardShortcut("e").disabled(
            model.currentPage == nil || model.isEditing)
          Button(localized("변경 이력"), action: model.history).disabled(model.currentPage == nil)
          Divider()
          Button(localized("전체 백업…"), action: model.backup)
          Button(localized("백업 가져오기…"), action: model.importBackup)
          Divider()
          Button(localized("AI 연결 설정"), action: { model.inspector = "connection" })
          Button(localized("위키 구조 점검"), action: { model.inspector = "lint" })
        }
        TextEditingCommands()
      }
    Settings {
      SettingsView(model: model, appearance: $appearance, language: languageSelection).tint(
        Theme.accent
      )
      .environment(\.locale, Localization.locale)
    }
  }
}
