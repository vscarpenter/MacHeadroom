import Foundation

enum AppIdentity {
  static let websiteURL = URL(string: "https://www.macheadroom.com/")!
  static let privacyPolicyURL = URL(string: "https://www.macheadroom.com/#privacy")!

  static var displayName: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? "System Headroom"
  }

  /// The bundle's marketing version and build number in a user-facing form.
  static var versionDescription: String {
    let short =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    return "Version \(short) (\(build))"
  }
}
