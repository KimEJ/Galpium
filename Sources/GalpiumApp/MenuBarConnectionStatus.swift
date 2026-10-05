import AppKit
import Combine
import GalpiumCore

@MainActor
final class MenuBarConnectionStatus: NSObject, NSMenuDelegate {
  private weak var model: AppModel?
  private weak var delegate: AppDelegate?
  let statusItem: NSStatusItem
  private var subscriptions = Set<AnyCancellable>()
  init(model: AppModel, delegate: AppDelegate) {
    self.model = model
    self.delegate = delegate
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    super.init()
    statusItem.autosaveName = "Galpium Connection"
    statusItem.button?.setAccessibilityIdentifier("galpium-menu-bar-status")
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.delegate = self
    statusItem.menu = menu
    model.connections.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
      self?.update()
    }.store(in: &subscriptions)
    update()
  }
  func remove() {
    subscriptions.removeAll()
    NSStatusBar.system.removeStatusItem(statusItem)
  }
  func menuWillOpen(_ menu: NSMenu) { update() }
  func update() {
    guard let model, let button = statusItem.button, let menu = statusItem.menu else { return }
    let status = model.connections
    let image = MenuBarBookIcon.image(connected: status.isConnected)
    button.image = image
    button.toolTip = "Galpium · " + status.label
    button.setAccessibilityLabel(localized("Galpium 연결 상태"))
    button.setAccessibilityValue(status.label)
    menu.removeAllItems()
    let heading = NSMenuItem(title: status.label, action: nil, keyEquivalent: "")
    heading.isEnabled = false
    menu.addItem(heading)
    for client in status.clients {
      let item = NSMenuItem(title: client.name, action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
    }
    menu.addItem(.separator())
    add(localized("Galpium 열기"), action: #selector(openWindow))
    add(localized("AI 연결 설정"), action: #selector(openConnection))
    let check = add(localized("MCP 연결 확인"), action: #selector(checkConnection))
    check.isEnabled = !model.isBusy
    menu.addItem(.separator())
    add(localized("Galpium 종료"), action: #selector(quit))
  }
  @discardableResult
  private func add(_ title: String, action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    statusItem.menu?.addItem(item)
    return item
  }
  @objc private func openWindow() { delegate?.showMainWindow() }
  @objc private func openConnection() {
    model?.inspector = "connection"
    delegate?.showMainWindow()
  }
  @objc private func checkConnection() {
    delegate?.showMainWindow()
    model?.testMCPConnection()
  }
  @objc private func quit() { NSApp.terminate(nil) }
}
