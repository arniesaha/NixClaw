import SwiftUI

/// Centralized runtime configuration manager.
///
/// Priority order for each value:
///   1. UserDefaults (user changed via Settings)
///   2. Info.plist   (from xcconfig at build time)
///   3. Hardcoded fallback
@MainActor
class AppConfig: ObservableObject {
  static let shared = AppConfig()

  // MARK: - Published properties (persisted to UserDefaults on change)

  @Published var assistantName: String {
    didSet { UserDefaults.standard.set(assistantName, forKey: "assistantName") }
  }

  @Published var accentColorHex: String {
    didSet { UserDefaults.standard.set(accentColorHex, forKey: "accentColorHex") }
  }

  @Published var geminiApiKey: String {
    didSet { UserDefaults.standard.set(geminiApiKey, forKey: "geminiApiKey") }
  }

  @Published var openClawScheme: String {
    didSet { UserDefaults.standard.set(openClawScheme, forKey: "openClawScheme") }
  }

  @Published var openClawHostname: String {
    didSet { UserDefaults.standard.set(openClawHostname, forKey: "openClawHostname") }
  }

  @Published var openClawPort: Int {
    didSet { UserDefaults.standard.set(openClawPort, forKey: "openClawPort") }
  }

  @Published var openClawToken: String {
    didSet { UserDefaults.standard.set(openClawToken, forKey: "openClawToken") }
  }

  // MARK: - Computed properties

  /// Display name of the app (from bundle, not runtime-changeable).
  var appName: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "NixClaw"
  }

  var isGeminiConfigured: Bool { !geminiApiKey.isEmpty }

  var isOpenClawConfigured: Bool { !openClawHostname.isEmpty && !openClawToken.isEmpty }

  /// True when the setup wizard should be shown (required config missing).
  var needsSetup: Bool { !isGeminiConfigured }

  var accentColor: Color { Color(hex: accentColorHex) ?? .blue }

  var openClawBaseURL: String {
    let scheme = openClawScheme.isEmpty ? "http" : openClawScheme
    return "\(scheme)://\(openClawHostname):\(openClawPort)"
  }

  // MARK: - Init

  private init() {
    assistantName = AppConfig.load("assistantName", plistKey: "DefaultAssistantName", fallback: "Assistant")
    accentColorHex = AppConfig.load("accentColorHex", plistKey: "DefaultAccentColor", fallback: "007AFF")
    geminiApiKey = AppConfig.load("geminiApiKey", plistKey: "GeminiApiKey", fallback: "")
    openClawScheme = AppConfig.load("openClawScheme", plistKey: "DefaultOpenClawScheme", fallback: "http")
    openClawHostname = AppConfig.load("openClawHostname", plistKey: "DefaultOpenClawHostname", fallback: "")
    openClawPort = AppConfig.loadInt("openClawPort", plistKey: "DefaultOpenClawPort", fallback: 18789)
    openClawToken = AppConfig.load("openClawToken", plistKey: "DefaultOpenClawToken", fallback: "")
  }

  // MARK: - Reset

  func resetToDefaults() {
    let keys = ["assistantName", "accentColorHex", "geminiApiKey", "openClawScheme", "openClawHostname", "openClawPort", "openClawToken"]
    keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }

    assistantName = AppConfig.load("assistantName", plistKey: "DefaultAssistantName", fallback: "Assistant")
    accentColorHex = AppConfig.load("accentColorHex", plistKey: "DefaultAccentColor", fallback: "007AFF")
    geminiApiKey = AppConfig.load("geminiApiKey", plistKey: "GeminiApiKey", fallback: "")
    openClawScheme = AppConfig.load("openClawScheme", plistKey: "DefaultOpenClawScheme", fallback: "http")
    openClawHostname = AppConfig.load("openClawHostname", plistKey: "DefaultOpenClawHostname", fallback: "")
    openClawPort = AppConfig.loadInt("openClawPort", plistKey: "DefaultOpenClawPort", fallback: 18789)
    openClawToken = AppConfig.load("openClawToken", plistKey: "DefaultOpenClawToken", fallback: "")
  }

  // MARK: - Helpers

  private static func load(_ udKey: String, plistKey: String, fallback: String) -> String {
    if let ud = UserDefaults.standard.string(forKey: udKey), !ud.isEmpty {
      return ud
    }
    if let plist = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String, !plist.isEmpty {
      return plist
    }
    return fallback
  }

  private static func loadInt(_ udKey: String, plistKey: String, fallback: Int) -> Int {
    // UserDefaults returns 0 for unset integers, so check existence explicitly
    if UserDefaults.standard.object(forKey: udKey) != nil {
      return UserDefaults.standard.integer(forKey: udKey)
    }
    if let plist = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String,
       let value = Int(plist) {
      return value
    }
    return fallback
  }
}

// MARK: - Color hex extension

extension Color {
  init?(hex: String) {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let r, g, b: UInt64
    switch hex.count {
    case 6:
      (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
    default:
      return nil
    }
    self.init(
      .sRGB,
      red: Double(r) / 255,
      green: Double(g) / 255,
      blue: Double(b) / 255,
      opacity: 1
    )
  }
}
