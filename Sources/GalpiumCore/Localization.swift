import Foundation

public enum Localization {
  public static let bundle = Bundle.module
  public static let preferenceKey = "language"
  public static var preferences: UserDefaults {
    if Bundle.main.bundleIdentifier == "io.galpium.mac" { return .standard }
    return UserDefaults(suiteName: "io.galpium.mac") ?? .standard
  }
  private static let languageBundles: [String: Bundle] = Dictionary(
    uniqueKeysWithValues: ["en", "ko", "ja"].compactMap { language in
      bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)).map {
        (language, $0)
      }
    })
  public static func resolvedLanguage(
    preference: String, systemLanguages: [String] = bundle.preferredLocalizations
  ) -> String {
    ["en", "ko", "ja"].contains(preference)
      ? preference
      : Bundle.preferredLocalizations(from: ["en", "ko", "ja"], forPreferences: systemLanguages)
        .first ?? "en"
  }
  public static var language: String {
    resolvedLanguage(preference: preferences.string(forKey: preferenceKey) ?? "system")
  }
  public static var locale: Locale { Locale(identifier: language) }
  public static func string(_ key: String, language: String) -> String {
    (languageBundles[language] ?? languageBundles["en"] ?? bundle).localizedString(
      forKey: key, value: nil, table: nil)
  }
}

public func localized(_ key: String, _ arguments: CVarArg...) -> String {
  let format = Localization.string(key, language: Localization.language)
  return arguments.isEmpty
    ? format : String(format: format, locale: Localization.locale, arguments: arguments)
}
