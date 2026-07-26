import Security

/// Whether this build may terminate other processes. The App Sandbox
/// denies every termination path (kill(2) EPERM, NSRunningApplication
/// refusals, appleevent-send seatbelt denial) per the July 26, 2026
/// spike in SANDBOX_NOTES.md, so the answer comes from our own code
/// signature: sandboxed builds never show quit UI.
enum TerminationCapability: Sendable, Equatable {
  case available
  case sandboxed

  static let current: TerminationCapability = {
    let task = SecTaskCreateFromSelf(nil)
    let value = task.flatMap {
      SecTaskCopyValueForEntitlement($0, "com.apple.security.app-sandbox" as CFString, nil)
    }
    let sandboxed = (value as? Bool) == true
    return sandboxed ? .sandboxed : .available
  }()

  var buildFlavorName: String {
    switch self {
    case .available: "Direct"
    case .sandboxed: "App Store"
    }
  }
}
