import Darwin
import Foundation

public struct MCPClientConnection: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var name: String
  public var version: String
  public var pid: Int32
  public var isBusy: Bool
  public var updatedAt: TimeInterval
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.id == rhs.id && lhs.name == rhs.name && lhs.version == rhs.version
      && lhs.pid == rhs.pid && lhs.isBusy == rhs.isBusy
  }
}

public enum MCPConnections {
  static let lifetime: TimeInterval = 8
  static func directory(for root: URL) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("Galpium-connections-\(getuid())", isDirectory: true)
      .appendingPathComponent(
        String(WikiStore.digest(Data(canonicalLibraryPath(root).utf8)).prefix(32)),
        isDirectory: true)
  }
  public static func clients(for root: URL, now: TimeInterval = Date().timeIntervalSince1970) throws
    -> [MCPClientConnection]
  {
    let directory = directory(for: root)
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    var clients = [MCPClientConnection]()
    for file in try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey])
    where file.pathExtension == "json" {
      let info = try? file.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
      guard info?.isSymbolicLink != true, (info?.fileSize ?? Int.max) <= 4096,
        let data = try? Data(contentsOf: file),
        let client = try? JSONDecoder().decode(MCPClientConnection.self, from: data),
        file.deletingPathExtension().lastPathComponent == client.id, client.pid > 0,
        client.updatedAt.isFinite, now - client.updatedAt >= -2, now - client.updatedAt <= lifetime,
        kill(client.pid, 0) == 0 || errno == EPERM
      else { continue }
      clients.append(client)
    }
    return clients.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
  }
}

/// Passive presence for a successfully initialized stdio client. Never records wiki contents.
final class MCPConnectionReporter: @unchecked Sendable {
  private let root: URL
  private let lock = NSLock()
  private var client: MCPClientConnection?
  private var timer: DispatchSourceTimer?
  init(root: URL) { self.root = root }
  deinit { close() }
  func initialize(name: String, version: String) {
    // The app's execution probe is not an external client connection.
    guard name != "Galpium connection check" else { return }
    lock.lock()
    defer { lock.unlock() }
    let clean = String(
      String.UnicodeScalarView(
        name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
      ).prefix(120))
    client = MCPClientConnection(
      id: client?.id ?? UUID().uuidString.lowercased(), name: clean.isEmpty ? "MCP Client" : clean,
      version: String(version.prefix(64)), pid: getpid(), isBusy: false,
      updatedAt: Date().timeIntervalSince1970)
    heartbeatLocked()
    if timer == nil {
      let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
      timer.schedule(deadline: .now() + 2, repeating: 2)
      timer.setEventHandler { [weak self] in self?.heartbeat() }
      self.timer = timer
      timer.resume()
    }
  }
  func setBusy(_ busy: Bool) {
    lock.lock()
    defer { lock.unlock() }
    client?.isBusy = busy
    heartbeatLocked()
  }
  private func heartbeat() {
    lock.lock()
    defer { lock.unlock() }
    heartbeatLocked()
  }
  private func heartbeatLocked() {
    guard var client else { return }
    client.updatedAt = Date().timeIntervalSince1970
    self.client = client
    let directory = MCPConnections.directory(for: root)
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: directory.deletingLastPathComponent().path)
      let file = directory.appendingPathComponent(client.id + ".json")
      try JSONEncoder().encode(client).write(to: file, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    } catch {
      // Presence failures must not interrupt MCP/library operations.
    }
  }
  func close() {
    lock.lock()
    defer { lock.unlock() }
    timer?.cancel()
    timer = nil
    if let client {
      try? FileManager.default.removeItem(
        at: MCPConnections.directory(for: root).appendingPathComponent(client.id + ".json"))
    }
    client = nil
  }
}
