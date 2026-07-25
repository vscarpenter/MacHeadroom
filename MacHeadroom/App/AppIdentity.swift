import Foundation

enum AppIdentity {
  static var displayName: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? "MacHeadroom"
  }

  /// "Version 0.1.0 (1)", from MARKETING_VERSION and CURRENT_PROJECT_VERSION.
  static var versionDescription: String {
    let short =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    return "Version \(short) (\(build))"
  }
}
