import Foundation
import Security

/// The App Sandbox boundary controls both process termination and access to
/// another process's physical footprint. Keep that one runtime fact separate
/// from the features that derive from it so their behavior cannot drift.
enum AppSandboxStatus: Sendable, Equatable {
  case enabled
  case disabled

  static let current: AppSandboxStatus = {
    let task = SecTaskCreateFromSelf(nil)
    let value = task.flatMap {
      SecTaskCopyValueForEntitlement($0, "com.apple.security.app-sandbox" as CFString, nil)
    }
    return (value as? Bool) == true ? .enabled : .disabled
  }()
}

enum AppIdentity {
  static let websiteURL = URL(string: "https://www.macheadroom.com/")!
  static let privacyPolicyURL = URL(string: "https://www.macheadroom.com/privacy.html")!

  /// An optional HTTPS endpoint configured only after the claim service is
  /// deployed and cleared for the App Store build. A blank setting disables
  /// the transfer UI and prevents all claim-service requests.
  static var directEditionClaimURL: URL? {
    guard let rawValue = Bundle.main.object(
      forInfoDictionaryKey: "DirectEditionClaimURL"
    ) as? String,
      let url = URL(string: rawValue),
      url.scheme == "https"
    else { return nil }
    return url
  }

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
