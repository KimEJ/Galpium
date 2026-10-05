import CSQLite
import Foundation

final class SQLite: @unchecked Sendable {
  private var db: OpaquePointer?
  private let lock = NSRecursiveLock()
  private var transactionDepth = 0
  init(url: URL, readOnly: Bool = false, derived: Bool = false) throws {
    let flags =
      readOnly
      ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
      : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
    if sqlite3_open_v2(url.path, &db, flags, nil) != SQLITE_OK {
      let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
      sqlite3_close(db)
      db = nil
      throw WikiError.storage("\(url.path): \(message)")
    }
    do {
      sqlite3_busy_timeout(db, 5000)
      if derived {
        let appID = Int(try query("PRAGMA application_id").first?.first ?? "0") ?? 0
        guard appID == 0 || appID == 0x4753_5243 else {
          throw WikiError.storage("invalid search cache")
        }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try execute("PRAGMA application_id=0x47535243")
        return
      }
      let version = Int(try query("PRAGMA user_version").first?.first ?? "0") ?? 0
      guard version <= 3 else { throw WikiError.storage("newer library format; update Galpium") }
      let appID = Int(try query("PRAGMA application_id").first?.first ?? "0") ?? 0
      let tables = Set(
        try query("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
          .compactMap(\.first))
      guard appID == 0 || appID == 0x474c_504d else {
        throw WikiError.storage("database belongs to another application")
      }
      if appID == 0 {
        guard
          (version == 0 && tables.isEmpty)
            || (version == 1
              && Set(["sources", "pages", "revisions", "attachments", "log", "drafts"]).isSubset(
                of: tables))
        else {
          throw WikiError.storage(
            "unrecognized database; choose a Galpium library or an empty folder")
        }
      }
      if readOnly { return }
      try execute("PRAGMA journal_mode=WAL")
      try execute("PRAGMA synchronous=FULL")
      try execute("PRAGMA foreign_keys=ON")
      try prepareSchema(version: version, url: url)
    } catch {
      sqlite3_close(db)
      db = nil
      throw error
    }
  }
  deinit { sqlite3_close(db) }
  private func statement(_ sql: String, _ values: [String]) throws -> OpaquePointer {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw error() }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (i, value) in values.enumerated() {
      if sqlite3_bind_text(stmt, Int32(i + 1), value, -1, transient) != SQLITE_OK {
        sqlite3_finalize(stmt)
        throw error()
      }
    }
    return stmt
  }
  private func error() -> WikiError { .storage(String(cString: sqlite3_errmsg(db))) }
  func execute(_ sql: String, _ values: [String] = []) throws {
    lock.lock()
    defer { lock.unlock() }
    let stmt = try statement(sql, values)
    defer { sqlite3_finalize(stmt) }
    var code = sqlite3_step(stmt)
    while code == SQLITE_ROW { code = sqlite3_step(stmt) }
    guard code == SQLITE_DONE else { throw error() }
  }
  func executeScript(_ sql: String) throws {
    lock.lock()
    defer { lock.unlock() }
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
  }
  func query(_ sql: String, _ values: [String] = []) throws -> [[String]] {
    lock.lock()
    defer { lock.unlock() }
    let stmt = try statement(sql, values)
    defer { sqlite3_finalize(stmt) }
    var rows = [[String]]()
    var code = sqlite3_step(stmt)
    while code == SQLITE_ROW {
      rows.append(
        (0..<sqlite3_column_count(stmt)).map { column in
          sqlite3_column_text(stmt, column).map { String(cString: $0) } ?? ""
        })
      code = sqlite3_step(stmt)
    }
    guard code == SQLITE_DONE else { throw error() }
    return rows
  }
  func transaction<T>(readOnly: Bool = false, _ block: () throws -> T) throws -> T {
    lock.lock()
    defer { lock.unlock() }
    let nested = transactionDepth > 0
    let savepoint = "nested_\(transactionDepth)"
    try execute(nested ? "SAVEPOINT \(savepoint)" : readOnly ? "BEGIN" : "BEGIN IMMEDIATE")
    transactionDepth += 1
    defer { transactionDepth -= 1 }
    do {
      let result = try block()
      try execute(nested ? "RELEASE \(savepoint)" : "COMMIT")
      return result
    } catch {
      try? execute(nested ? "ROLLBACK TO \(savepoint)" : "ROLLBACK")
      if nested { try? execute("RELEASE \(savepoint)") }
      throw error
    }
  }
  func backup(to url: URL) throws {
    lock.lock()
    defer { lock.unlock() }
    var destination: OpaquePointer?
    guard sqlite3_open(url.path, &destination) == SQLITE_OK else {
      let message = destination.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
      sqlite3_close(destination)
      throw WikiError.storage("backup destination \(url.path): \(message)")
    }
    defer { sqlite3_close(destination) }
    guard let backup = sqlite3_backup_init(destination, "main", db, "main") else {
      throw WikiError.storage("backup initialization failed")
    }
    let code = sqlite3_backup_step(backup, -1)
    let finished = sqlite3_backup_finish(backup)
    guard code == SQLITE_DONE, finished == SQLITE_OK else {
      throw WikiError.storage("backup incomplete")
    }
    // The backup copies the WAL-mode header. Convert the standalone snapshot
    // to DELETE mode so read-only restores never need absent WAL/SHM files.
    guard sqlite3_exec(destination, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else {
      throw WikiError.storage("backup journal finalization failed")
    }
  }
}
