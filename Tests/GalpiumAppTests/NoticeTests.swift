import Foundation
import XCTest

@testable import GalpiumApp

final class NoticeTests: XCTestCase {
  @MainActor
  func testRepeatedNoticeRestartsDismissalAndErrorsRemainVisible() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(root: root)
    model.error = "persistent error"
    model.notice = "complete"
    try await Task.sleep(for: .milliseconds(2500))
    model.notice = "complete"
    try await Task.sleep(for: .milliseconds(2000))
    XCTAssertEqual(model.notice, "complete")
    try await Task.sleep(for: .milliseconds(2500))
    XCTAssertNil(model.notice)
    XCTAssertEqual(model.error, "persistent error")
  }
  @MainActor
  func testManualCloseCancelsOldDeadlineForNextNotice() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(root: root)
    model.notice = "first"
    try await Task.sleep(for: .milliseconds(2500))
    model.notice = nil
    model.notice = "second"
    try await Task.sleep(for: .milliseconds(2000))
    XCTAssertEqual(model.notice, "second")
    model.notice = nil
  }
}
