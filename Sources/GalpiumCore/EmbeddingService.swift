import CryptoKit
import Darwin
import Foundation

func canonicalLibraryPath(_ url: URL) -> String {
  guard let pointer = realpath(url.path, nil) else { return url.standardizedFileURL.path }
  defer { free(pointer) }
  return String(cString: pointer)
}

struct EmbeddingRequest: Codable, Sendable {
  var operation: String
  var text: String? = nil
}
struct EmbeddingResponse: Codable, Sendable {
  var vector: [Float]? = nil
  var error: String? = nil
  var workerPID: Int32? = nil
  var runtimeMode: String? = nil
  var supervisorPID: Int32? = nil
}

struct EmbeddingSocket {
  let directory: URL
  let socketPath: String
  init(root: URL) throws {
    directory = URL(fileURLWithPath: "/private/tmp/Galpium-\(getuid())", isDirectory: true)
    let created = mkdir(directory.path, 0o700)
    guard created == 0 || errno == EEXIST else {
      throw WikiError.storage("embedding socket directory")
    }
    var info = stat()
    guard lstat(directory.path, &info) == 0, info.st_uid == getuid(),
      (info.st_mode & S_IFMT) == S_IFDIR, info.st_mode & 0o077 == 0
    else { throw WikiError.storage("unsafe embedding socket directory") }
    let id = String(
      WikiStore.digest(Data((canonicalLibraryPath(root) + "\n" + EmbeddingAssets.identity).utf8))
        .prefix(
          24))
    socketPath = directory.appendingPathComponent(id + ".sock").path
  }
  func address() throws -> sockaddr_un {
    var value = sockaddr_un()
    value.sun_family = sa_family_t(AF_UNIX)
    value.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let bytes = Array(socketPath.utf8) + [0]
    guard bytes.count <= MemoryLayout.size(ofValue: value.sun_path) else {
      throw WikiError.invalid("socket path")
    }
    withUnsafeMutableBytes(of: &value.sun_path) { dest in
      for (i, byte) in bytes.enumerated() { dest[i] = byte }
    }
    return value
  }
  func connect() throws -> Int32 {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw WikiError.storage("embedding socket") }
    var address = try address()
    let result = withUnsafePointer(to: &address) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard result == 0 else {
      close(fd)
      throw WikiError.storage("embedding connection")
    }
    Self.configure(fd)
    return fd
  }
  static func configure(_ fd: Int32) {
    var timeout = timeval(tv_sec: 30, tv_usec: 0)
    _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var yes: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
    _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
  }
  static func send<T: Encodable>(_ value: T, fd: Int32) throws {
    var data = try JSONEncoder().encode(value)
    data.append(10)
    try data.withUnsafeBytes { bytes in
      var offset = 0
      while offset < data.count {
        let count = Darwin.write(fd, bytes.baseAddress! + offset, data.count - offset)
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { throw WikiError.storage("embedding write") }
        offset += count
      }
    }
  }
  static func receive<T: Decodable>(_ type: T.Type, fd: Int32) throws -> T {
    var data = Data()
    var bytes = [UInt8](repeating: 0, count: 4096)
    while data.count <= 1024 * 1024 {
      let count = Darwin.read(fd, &bytes, bytes.count)
      if count < 0 && errno == EINTR { continue }
      guard count > 0 else { throw WikiError.storage("embedding read timeout") }
      data.append(contentsOf: bytes.prefix(count))
      if let end = data.firstIndex(of: 10) {
        return try JSONDecoder().decode(type, from: data.prefix(upTo: end))
      }
    }
    throw WikiError.invalid("embedding message limit")
  }
}

struct EmbeddingClient {
  let root: URL
  func request(_ request: EmbeddingRequest) throws -> EmbeddingResponse {
    let socket = try EmbeddingSocket(root: root)
    var fd = try? socket.connect()
    if fd == nil {
      guard EmbeddingAssets.available else {
        throw WikiError.storage("embedding assets unavailable")
      }
      let lock = open(
        socket.socketPath + ".start", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
      guard lock >= 0 else { throw WikiError.storage("embedding startup lock") }
      defer {
        _ = flock(lock, LOCK_UN)
        close(lock)
      }
      guard flock(lock, LOCK_EX) == 0 else { throw WikiError.storage("embedding startup lock") }
      fd = try? socket.connect()
      if fd == nil {
        let process = Process()
        process.executableURL = EmbeddingAssets.worker
        process.arguments = ["--library", root.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(20)
        repeat {
          Thread.sleep(forTimeInterval: 0.05)
          fd = try? socket.connect()
          if fd != nil { break }
        } while Date() < deadline && process.isRunning
      }
    }
    guard let fd else { throw WikiError.storage("embedding worker unavailable") }
    defer { close(fd) }
    try EmbeddingSocket.send(request, fd: fd)
    let response = try EmbeddingSocket.receive(EmbeddingResponse.self, fd: fd)
    if let error = response.error { throw WikiError.storage(error) }
    return response
  }
}

enum EmbeddingRuntimeMode: String {
  case text
  case multimodal
}

final class EmbeddingRuntime {
  private var supervisor: Process?
  private var configuredMode: EmbeddingRuntimeMode?
  private var assetsValidated = false
  private var port: UInt16 = 0
  private var key = ""
  private let socket: EmbeddingSocket
  private let session: URLSession
  var mode: EmbeddingRuntimeMode? {
    supervisor?.isRunning == true ? configuredMode : nil
  }
  var supervisorPID: Int32? {
    supervisor?.isRunning == true ? supervisor?.processIdentifier : nil
  }
  init(socket: EmbeddingSocket) {
    self.socket = socket
    let config = URLSessionConfiguration.ephemeral
    config.connectionProxyDictionary = [:]
    config.timeoutIntervalForRequest = 90
    config.timeoutIntervalForResource = 100
    session = URLSession(configuration: config)
  }
  deinit { stop() }
  func stop() {
    if let process = supervisor, process.isRunning {
      process.terminate()
      let end = Date().addingTimeInterval(4)
      while process.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.02) }
      if process.isRunning {
        _ = kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
      }
    }
    supervisor = nil
    configuredMode = nil
    port = 0
    key = ""
    try? FileManager.default.removeItem(atPath: socket.socketPath + ".key")
  }
  /// Encoder weights are released only once the indexing queue has drained.
  /// Queries arriving during indexing reuse its full model and identical text vector space.
  func releaseMedia() throws {
    guard mode == .multimodal else { return }
    stop()
    try ensureStarted(mode: .text)
  }
  static func validateAsset(_ url: URL, expectedHash: String) throws {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty {
      hash.update(data: bytes)
    }
    guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == expectedHash
    else { throw WikiError.storage("embedding asset checksum") }
  }
  private func ensureStarted(mode requestedMode: EmbeddingRuntimeMode = .text) throws {
    if let activeMode = mode,
      activeMode == requestedMode || activeMode == .multimodal && requestedMode == .text
    {
      return
    }
    stop()
    if !assetsValidated {
      try Self.validateAsset(EmbeddingAssets.model, expectedHash: EmbeddingAssets.modelHash)
      try Self.validateAsset(EmbeddingAssets.projector, expectedHash: EmbeddingAssets.projectorHash)
      assetsValidated = true
    }
    let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { throw WikiError.storage("embedding port") }
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let bound = withUnsafePointer(to: &address) { p in
      p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let named = withUnsafeMutablePointer(to: &address) { p in
      p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
    }
    close(fd)
    guard bound == 0, named == 0 else { throw WikiError.storage("embedding port") }
    port = UInt16(bigEndian: address.sin_port)
    key = UUID().uuidString + UUID().uuidString
    let keyFile = socket.socketPath + ".key"
    guard
      FileManager.default.createFile(
        atPath: keyFile, contents: Data(key.utf8), attributes: [.posixPermissions: 0o600])
    else { throw WikiError.storage("embedding runtime key") }
    let process = Process()
    process.executableURL = EmbeddingAssets.worker
    process.arguments = [
      "--supervise", String(getpid()), "--port", String(port), "--key-file", keyFile,
      "--mode", requestedMode.rawValue,
    ]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    supervisor = process
    configuredMode = requestedMode
    let deadline = Date().addingTimeInterval(60)
    while Date() < deadline, process.isRunning {
      if (try? http("/health", body: nil, timeout: 1)) != nil { return }
      Thread.sleep(forTimeInterval: 0.05)
    }
    stop()
    throw WikiError.storage("embedding runtime startup failed")
  }
  private func http(_ endpoint: String, body: [String: Any]?, timeout: TimeInterval = 90) throws
    -> [String: Any]
  {
    let url = URL(string: "http://127.0.0.1:\(port)\(endpoint)")!
    var request = URLRequest(url: url, timeoutInterval: timeout)
    request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    if let body {
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let completed = DispatchSemaphore(value: 0)
    let output = HTTPResult()
    let task = session.dataTask(with: request) { data, response, error in
      output.value = (data, response as? HTTPURLResponse, error)
      completed.signal()
    }
    task.resume()
    guard completed.wait(timeout: .now() + timeout + 1) == .success else {
      task.cancel()
      throw WikiError.storage("embedding request timed out")
    }
    guard let (data, response, error) = output.value, error == nil, let data,
      response?.statusCode == 200,
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw WikiError.storage("embedding request failed") }
    return object
  }
  func tokenCount(_ text: String) throws -> Int {
    try ensureStarted()
    guard
      let tokens = try http(
        "/tokenize", body: ["content": text, "add_special": true, "parse_special": false])[
          "tokens"] as? [Int]
    else { throw WikiError.storage("embedding tokenizer") }
    return tokens.count
  }
  static func vector(from response: [String: Any]) throws -> [Float] {
    guard let rows = response["data"] as? [[String: Any]], rows.count == 1,
      let numbers = rows.first?["embedding"] as? [NSNumber], numbers.count == 768
    else { throw WikiError.storage("embedding shape") }
    let vector = numbers.map(\.floatValue)
    let norm = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
    guard vector.allSatisfy(\.isFinite), norm.isFinite, norm > 0.01 else {
      throw WikiError.storage("embedding values")
    }
    return vector.map { $0 / norm }
  }
  func embed(_ text: String) throws -> [Float] {
    guard try tokenCount(text) <= 512 else { throw WikiError.invalid("embedding context limit") }
    return try Self.vector(
      from: http(
        "/v1/embeddings", body: ["input": text, "encoding_format": "float"]))
  }
  static func mediaBody(data: Data, kind: String) throws -> [String: Any] {
    guard !data.isEmpty, data.count <= 16 * 1024 * 1024 else {
      throw WikiError.invalid("embedding media size")
    }
    let part: [String: Any]
    switch kind {
    case "image":
      part = [
        "type": "image_url",
        "image_url": ["url": "data:image/jpeg;base64," + data.base64EncodedString()],
      ]
    case "audio":
      part = [
        "type": "input_audio",
        "input_audio": ["data": data.base64EncodedString(), "format": "wav"],
      ]
    default: throw WikiError.invalid("embedding media kind")
    }
    return ["input": [["content": [part]]], "encoding_format": "float"]
  }
  func embedMedia(data: Data, kind: String) throws -> [Float] {
    let body = try Self.mediaBody(data: data, kind: kind)
    try ensureStarted(mode: .multimodal)
    return try Self.vector(from: http("/v1/embeddings", body: body))
  }
}
private final class HTTPResult: @unchecked Sendable {
  var value: (Data?, HTTPURLResponse?, Error?)?
}

public enum EmbeddingWorker {
  static func runtimeArguments(mode: EmbeddingRuntimeMode, port: String, keyFile: String)
    -> [String]
  {
    let context = mode == .multimodal ? "8192" : "2048"
    var arguments = [
      "-m", EmbeddingAssets.model.path, "--embedding", "--pooling", "mean", "--ctx-size", context,
      "--batch-size", context, "--ubatch-size", context, "--parallel", "1", "--threads", "2",
      "--threads-batch", "2", "--threads-http", "1", "--gpu-layers", "99", "--cache-ram", "0",
      "--cache-type-k", "f32", "--cache-type-v", "f32", "--flash-attn", "off",
      "--no-warmup", "--host", "127.0.0.1", "--port", port, "--api-key-file", keyFile, "--no-ui",
      "--no-agent", "--no-ui-mcp-proxy", "--cors-origins", "null", "--no-cors-credentials",
      "--sleep-idle-seconds", "60",
    ]
    if mode == .multimodal {
      arguments += ["--mmproj", EmbeddingAssets.projector.path, "--image-max-tokens", "1120"]
    } else {
      arguments += ["--no-mmproj"]
    }
    return arguments
  }
  public static func supervise(owner: Int32, port: String, keyFile: String, mode: String = "text")
    throws
  {
    guard let mode = EmbeddingRuntimeMode(rawValue: mode) else {
      throw WikiError.invalid("embedding runtime mode")
    }
    let stopped = WorkerStop()
    signal(SIGTERM, SIG_IGN)
    signal(SIGINT, SIG_IGN)
    let sources = [SIGTERM, SIGINT].map { number -> DispatchSourceSignal in
      let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
      source.setEventHandler { stopped.stop() }
      source.resume()
      return source
    }
    defer { for source in sources { source.cancel() } }
    let process = Process()
    process.executableURL = EmbeddingAssets.runtime
    process.currentDirectoryURL = EmbeddingAssets.runtime.deletingLastPathComponent()
    process.arguments = runtimeArguments(mode: mode, port: port, keyFile: keyFile)
    process.environment = ProcessInfo.processInfo.environment.filter {
      !$0.key.hasPrefix("LLAMA_") && !$0.key.hasPrefix("GGML_") && !$0.key.hasPrefix("MTMD_")
    }
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    while process.isRunning && !stopped.value && getppid() == owner {
      Thread.sleep(forTimeInterval: 0.1)
    }
    if process.isRunning {
      process.terminate()
      let deadline = Date().addingTimeInterval(2)
      while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
      if process.isRunning {
        _ = kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
      }
    }
  }
  public static func run(root: URL) throws {
    let socket = try EmbeddingSocket(root: root)
    let lease = open(socket.socketPath + ".lease", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard lease >= 0 else { throw WikiError.storage("embedding lease") }
    defer { close(lease) }
    guard flock(lease, LOCK_EX | LOCK_NB) == 0 else { return }
    defer { _ = flock(lease, LOCK_UN) }
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw WikiError.storage("embedding listener") }
    defer {
      close(fd)
      unlink(socket.socketPath)
    }
    unlink(socket.socketPath)
    var address = try socket.address()
    let bound = withUnsafePointer(to: &address) { p in
      p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard bound == 0, chmod(socket.socketPath, 0o600) == 0, listen(fd, 16) == 0 else {
      throw WikiError.storage("embedding listener")
    }
    let store = try WikiStore(root: root)
    let cache = try SemanticCache(root: root)
    let runtime = EmbeddingRuntime(socket: socket)
    let stopped = WorkerStop()
    signal(SIGTERM, SIG_IGN)
    signal(SIGINT, SIG_IGN)
    let signals = [SIGTERM, SIGINT].map { number -> DispatchSourceSignal in
      let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
      source.setEventHandler { stopped.stop() }
      source.resume()
      return source
    }
    defer {
      for source in signals { source.cancel() }
      runtime.stop()
    }
    let failureFile = root.appendingPathComponent("search-cache/" + EmbeddingAssets.failureFilename)
    let idle =
      Double(ProcessInfo.processInfo.environment["GALPIUM_EMBEDDING_IDLE_SECONDS"] ?? "60") ?? 60
    var lastWork = Date()
    var pending = [String]()
    var current: WikiPage?
    var currentKey: String?
    var passages = [SemanticPassage]()
    var completed = [SemanticPassage]()
    func response(vector: [Float]? = nil) -> EmbeddingResponse {
      EmbeddingResponse(
        vector: vector, workerPID: getpid(), runtimeMode: runtime.mode?.rawValue,
        supervisorPID: runtime.supervisorPID)
    }
    func queueIndex() throws {
      let revisions = try store.semanticRevisions()
      let keys = revisions.keys.sorted()
      pending = []
      for key in keys {
        guard let revision = revisions[key],
          try !cache.recentlyFailed(key, revision: revision)
        else { continue }
        let page: WikiPage
        do { page = try store.semanticDocument(key) } catch {
          try cache.recordFailure(WikiPage(slug: key, title: "", body: "", revision: revision))
          continue
        }
        if try !cache.missing([page]).isEmpty { pending.append(key) }
      }
      try cache.prune(Set(keys))
    }
    while !stopped.value {
      var pollFD = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
      let busy = current != nil || !pending.isEmpty
      if poll(&pollFD, 1, busy ? 0 : 250) > 0 && pollFD.revents & Int16(POLLIN) != 0 {
        let connection = accept(fd, nil, nil)
        if connection >= 0 {
          EmbeddingSocket.configure(connection)
          do {
            let request = try EmbeddingSocket.receive(EmbeddingRequest.self, fd: connection)
            switch request.operation {
            case "query":
              let query = try WikiValidation.text(
                request.text ?? "", field: "query", bytes: 800, count: 200)
              let vector = try runtime.embed("task: search result | query: " + query)
              try? FileManager.default.removeItem(at: failureFile)
              try EmbeddingSocket.send(
                response(vector: vector), fd: connection)
              lastWork = Date()
              if !busy { try queueIndex() }
            case "index":
              if !busy { try queueIndex() }
              try EmbeddingSocket.send(response(), fd: connection)
            case "status":
              try EmbeddingSocket.send(response(), fd: connection)
            case "shutdown":
              stopped.stop()
              try EmbeddingSocket.send(response(), fd: connection)
            default: throw WikiError.invalid("embedding operation")
            }
          } catch {
            try? EmbeddingSocket.send(
              EmbeddingResponse(error: error.localizedDescription), fd: connection)
          }
          close(connection)
          continue
        }
      }
      do {
        if current == nil, !pending.isEmpty {
          let key = pending.removeFirst()
          currentKey = key
          current = try store.semanticDocument(key)
          guard let current else { continue }
          let originalPages =
            current.slug.hasPrefix("material:")
            ? try store.materialExtraction(String(current.slug.dropFirst(9)))?.pages : nil
          passages = try buildPassages(current, originalPages: originalPages) {
            try runtime.tokenCount($0)
          }
          for media in try store.semanticMediaItems(current.slug) {
            let id = WikiStore.digest(Data((EmbeddingAssets.identity + "\n" + media.identity).utf8))
            passages.append(
              SemanticPassage(
                id: id, slug: current.slug, digest: SemanticCache.digest(current),
                heading: media.heading, excerpt: media.excerpt, input: "", media: media))
          }
          guard !passages.isEmpty else {
            throw WikiError.invalid("material has no searchable content")
          }
          completed = []
        }
        if let page = current {
          guard let latest = try? store.semanticDocument(page.slug), latest.status == "active",
            SemanticCache.digest(latest) == SemanticCache.digest(page)
          else {
            current = nil
            currentKey = nil
            try queueIndex()
            continue
          }
          if !passages.isEmpty {
            let passage = passages.removeFirst()
            if try cache.vector(passage.id) == nil {
              let vector: [Float]
              if let media = passage.media {
                vector = try runtime.embedMedia(
                  data: store.semanticMediaData(media), kind: media.kind)
              } else {
                vector = try runtime.embed(passage.input)
              }
              try cache.saveVector(passage.id, vector)
            }
            completed.append(passage)
            lastWork = Date()
            try? FileManager.default.removeItem(at: failureFile)
          } else {
            try cache.replace(page, passages: completed)
            current = nil
            currentKey = nil
            if pending.isEmpty { try queueIndex() }
          }
        }
      } catch {
        if let page = current {
          try? cache.recordFailure(page)
        } else if let currentKey, let revision = try? store.semanticRevisions()[currentKey] {
          try? cache.recordFailure(
            WikiPage(slug: currentKey, title: "", body: "", revision: revision))
        }
        current = nil
        currentKey = nil
        passages = []
        completed = []
        runtime.stop()
        // A failed original cools down independently; other documents keep indexing.
      }
      if current == nil && pending.isEmpty {
        do { try runtime.releaseMedia() } catch { runtime.stop() }
        if Date().timeIntervalSince(lastWork) >= max(1, idle) { break }
      }
    }
  }
  static func buildPassages(
    _ page: WikiPage, originalPages: [MaterialTextPage]? = nil,
    tokenCount: (String) throws -> Int
  ) throws -> [SemanticPassage] {
    if page.slug.hasPrefix("material:"), originalPages == nil,
      page.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return []
    }
    var result = [SemanticPassage]()
    var heading = ""
    var pageNumber: Int?
    var title = String(page.title.prefix(80)).replacingOccurrences(of: "\n", with: " ")
    func prefix() throws -> String {
      while try tokenCount("title: \(title) | text: " + heading) > 128 {
        guard !title.isEmpty || !heading.isEmpty else {
          throw WikiError.invalid("embedding title context")
        }
        if heading.count > title.count {
          heading = String(heading.prefix(heading.count / 2))
        } else {
          title = String(title.prefix(title.count / 2))
        }
      }
      return "title: \(title) | text: " + (heading.isEmpty ? "" : heading + "\n")
    }
    func append(_ text: String) throws {
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
      let input = try prefix() + text
      if try tokenCount(input) > 384 {
        guard text.count > 1 else { throw WikiError.invalid("passage context") }
        let middle = text.index(text.startIndex, offsetBy: text.count / 2)
        try append(String(text[..<middle]))
        try append(String(text[middle...]))
        return
      }
      let id = WikiStore.digest(Data((EmbeddingAssets.identity + "\n" + input).utf8))
      result.append(
        SemanticPassage(
          id: id, slug: page.slug, digest: SemanticCache.digest(page), heading: heading,
          excerpt: String(text.prefix(480)), input: input,
          pageNumber: pageNumber))
    }
    func appendBounded(_ text: String) throws {
      // Bound tokenizer request sizes even for a single enormous paragraph.
      var remaining = text[...]
      while !remaining.isEmpty {
        let end = remaining.index(remaining.startIndex, offsetBy: min(500, remaining.count))
        try append(String(remaining[..<end]))
        remaining = remaining[end...]
      }
    }
    if let originalPages {
      // Original text is data. Its own headings can never alter its structural PDF page.
      for original in originalPages {
        pageNumber = original.number
        heading = "Page \(original.number)"
        for paragraph in original.text.components(separatedBy: "\n\n") {
          try appendBounded(paragraph)
        }
      }
    } else {
      for block in Markdown.blocks(page.body) {
        if block.kind == "heading" {
          heading = String(block.text.prefix(80))
          continue
        }
        let text =
          ["table", "list", "ordered"].contains(block.kind)
          ? block.rows.map { $0.joined(separator: " | ") }.joined(separator: "\n") : block.text
        try appendBounded(text)
      }
    }
    if result.isEmpty && !page.slug.hasPrefix("material:") { try append(page.title) }
    var seen = Set<String>()
    return result.filter { seen.insert($0.id).inserted }
  }
}
private final class WorkerStop: @unchecked Sendable {
  private let lock = NSLock()
  private var stopped = false
  var value: Bool {
    lock.lock()
    defer { lock.unlock() }
    return stopped
  }
  func stop() {
    lock.lock()
    stopped = true
    lock.unlock()
  }
}
