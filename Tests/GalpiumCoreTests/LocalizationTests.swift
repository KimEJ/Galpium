import Foundation
import XCTest

@testable import GalpiumCore

final class LocalizationTests: XCTestCase {
  func testExplicitLanguageOverridesSystemAndUsesMatchingBundle() {
    XCTAssertEqual(Localization.resolvedLanguage(preference: "ja", systemLanguages: ["ko"]), "ja")
    XCTAssertEqual(Localization.resolvedLanguage(preference: "ko", systemLanguages: ["en"]), "ko")
    XCTAssertEqual(Localization.resolvedLanguage(preference: "en", systemLanguages: ["ja"]), "en")
    XCTAssertEqual(
      Localization.resolvedLanguage(preference: "system", systemLanguages: ["ja-JP"]), "ja")
    XCTAssertEqual(
      Localization.resolvedLanguage(preference: "invalid", systemLanguages: ["ko-KR"]), "ko")
    XCTAssertEqual(Localization.string("저장", language: "en"), "Save")
    XCTAssertEqual(Localization.string("저장", language: "ja"), "保存")
    XCTAssertEqual(Localization.string("저장", language: "ko"), "저장")
  }
  private func table(_ language: String) throws -> [String: String] {
    let url = try XCTUnwrap(
      Localization.bundle.url(
        forResource: "Localizable", withExtension: "strings", subdirectory: nil,
        localization: language))
    return try XCTUnwrap(
      PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        as? [String: String])
  }

  func testAllTranslationsHaveMatchingKeysAndFormatArguments() throws {
    let english = try table("en")
    XCTAssertGreaterThan(english.count, 200)
    let formats = try NSRegularExpression(pattern: "%(@|ld)")
    func arguments(_ value: String) -> [String] {
      formats.matches(in: value, range: NSRange(value.startIndex..., in: value)).map {
        (value as NSString).substring(with: $0.range)
      }
    }
    for language in ["en", "ko", "ja"] {
      let translated = try table(language)
      XCTAssertEqual(Set(english.keys), Set(translated.keys))
      for (key, value) in translated {
        XCTAssertFalse(value.isEmpty, "\(language): \(key)")
        XCTAssertEqual(arguments(key), arguments(value), "\(language): \(key)")
      }
    }
    XCTAssertEqual(english["저장"], "Save")
    XCTAssertEqual(try table("ja")["저장"], "保存")
    XCTAssertEqual(try table("ko")["저장"], "저장")
  }

  func testNativeLanguageMatchingSupportsRegionalPreferencesAndEnglishFallback() {
    let bundle = Localization.bundle
    XCTAssertEqual(bundle.developmentLocalization, "en")
    XCTAssertEqual(Set(bundle.localizations), ["en", "ja", "ko"])
    for (preferences, expected) in [
      (["ja-JP", "en-US"], "ja"), (["ko-KR", "ja-JP"], "ko"),
      (["en-GB", "ko-KR"], "en"), (["fr-FR", "ja-JP"], "ja"), (["fr-FR"], "en"),
    ] {
      XCTAssertEqual(
        Bundle.preferredLocalizations(from: ["en", "ko", "ja"], forPreferences: preferences).first,
        expected)
    }
  }

  func testTranslationsFormatRevisionAndLeaveUserTextUntouched() throws {
    for language in ["en", "ko", "ja"] {
      let values = try table(language)
      let title = "한글 日本語 😀 100%"
      let format = try XCTUnwrap(values["최신 제목: %@"])
      XCTAssertTrue(String(format: format, title).hasSuffix(title))
      let revision = try XCTUnwrap(values["r%ld으로 복원할까요?"])
      XCTAssertTrue(String(format: revision, 123).contains("r123"))
    }
    XCTAssertTrue(localized("수정 %@ · 개정 %ld", "DATE", 123).contains("DATE"))
    XCTAssertTrue(localized("수정 %@ · 개정 %ld", "DATE", 123).contains("123"))
  }
}
