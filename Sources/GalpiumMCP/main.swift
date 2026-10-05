import Darwin
import Foundation
import GalpiumCore

do {
  let root: URL
  let args = CommandLine.arguments
  if args.count > 1 {
    guard args.count == 3, args[1] == "--library", args[2].hasPrefix("/") else {
      FileHandle.standardError.write(
        Data("Usage: galpium-mcp [--library /absolute/library/path]\n".utf8))
      exit(2)
    }
    root = URL(fileURLWithPath: args[2], isDirectory: true)
  } else {
    root = WikiStore.defaultRoot
  }
  let server = MCPServer(store: try WikiStore(root: root), reportConnections: true)
  var buffer = Data()
  var dropping = false
  func respond(_ result: [String: Any]?) throws {
    guard let result else { return }
    var data = try JSONSerialization.data(
      withJSONObject: result, options: [.sortedKeys, .withoutEscapingSlashes])
    data.append(10)
    try FileHandle.standardOutput.write(contentsOf: data)
  }
  var chunk = [UInt8](repeating: 0, count: 65536)
  while true {
    let count = Darwin.read(STDIN_FILENO, &chunk, chunk.count)
    if count == 0 { break }
    if count < 0 {
      if errno == EINTR { continue }
      throw WikiError.storage("stdin read failed")
    }
    for byte in chunk.prefix(count) {
      if byte == 10 {
        if !dropping && !buffer.isEmpty { try respond(server.handle(buffer)) }
        buffer.removeAll(keepingCapacity: true)
        dropping = false
      } else if !dropping {
        buffer.append(byte)
        if buffer.count > 4 * 1024 * 1024 {
          try respond([
            "jsonrpc": "2.0", "id": NSNull(),
            "error": ["code": -32700, "message": "Message exceeds 4 MiB"],
          ])
          buffer.removeAll(keepingCapacity: false)
          dropping = true
        }
      }
    }
  }
  if !dropping && !buffer.isEmpty { try respond(server.handle(buffer)) }
} catch {
  FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
  exit(1)
}
