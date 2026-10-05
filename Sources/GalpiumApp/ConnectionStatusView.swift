import GalpiumCore
import SwiftUI

@MainActor
final class MCPConnectionStatus: ObservableObject {
  @Published private(set) var clients = [MCPClientConnection]()
  @Published private(set) var unavailable = false
  var isConnected: Bool { !clients.isEmpty }
  var isWorking: Bool { clients.contains { $0.isBusy } }
  var label: String {
    unavailable
      ? localized("연결 상태 확인 불가")
      : isWorking
        ? localized("AI 작업 중") : isConnected ? localized("AI 연결됨") : localized("AI 연결 안 됨")
  }
  var symbol: String {
    unavailable
      ? "exclamationmark.circle"
      : isWorking
        ? "arrow.triangle.2.circlepath.circle.fill"
        : isConnected ? "link.circle.fill" : "link.circle"
  }
  func refresh(root: URL?) {
    guard let root else {
      clients = []
      unavailable = false
      return
    }
    do {
      let current = try MCPConnections.clients(for: root)
      if clients != current { clients = current }
      if unavailable { unavailable = false }
    } catch {
      if !unavailable { unavailable = true }
      if !clients.isEmpty { clients = [] }
    }
  }
}

struct ConnectionStatusDetails: View {
  @ObservedObject var status: MCPConnectionStatus
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(status.label, systemImage: status.symbol).font(.headline)
        .foregroundStyle(
          status.unavailable ? Color.orange : status.isConnected ? Theme.accent : Color.secondary)
      if !status.clients.isEmpty {
        ForEach(status.clients) { client in
          HStack {
            Text(client.name).lineLimit(1).help(client.name)
            Spacer()
            if client.isBusy {
              ProgressView().controlSize(.small).accessibilityLabel(localized("AI 작업 중"))
            }
          }.font(.callout)
        }
      }
    }
  }
}
