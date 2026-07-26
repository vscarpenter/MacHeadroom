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

import AppKit
import os

enum TerminationOutcome: Sendable, Equatable {
  case requestedAppQuit
  case appRefused
  case signaled
  case signalFailed(errno: Int32)
  case staleIdentity
  case processGone
}

/// Thin seam over NSRunningApplication so tests can fake the app path;
/// the sandboxed test host cannot exercise the real one (SANDBOX_NOTES).
@MainActor
struct RunningAppHandle {
  var terminate: () -> Bool
  var forceTerminate: () -> Bool
}

/// Maps a popover row to the one termination primitive that fits it.
/// App groups get NSRunningApplication (instance-bound, PID-reuse safe,
/// helpers follow their app). Standalone groups get a BSD signal behind
/// a startIdentity revalidation. Groups only; never child pids.
@MainActor
struct ProcessTerminator {
  var runningApplication: (Int32) -> RunningAppHandle?
  var currentStartIdentity: (Int32) -> String?
  var sendSignal: (Int32, Int32) -> Int32

  private static let log = Logger(
    subsystem: "com.vinnycarpenter.MacHeadroom", category: "termination")

  static func live() -> ProcessTerminator {
    ProcessTerminator(
      runningApplication: { pid in
        guard let app = NSRunningApplication(processIdentifier: pid) else {
          return nil
        }
        return RunningAppHandle(
          terminate: { app.terminate() },
          forceTerminate: { app.forceTerminate() })
      },
      currentStartIdentity: ProcessTableSampler.startIdentity(of:),
      sendSignal: { pid, signal in kill(pid, signal) })
  }

  func quit(_ group: AppGroup) -> TerminationOutcome {
    act(on: group, force: false)
  }

  func forceQuit(_ group: AppGroup) -> TerminationOutcome {
    act(on: group, force: true)
  }

  private func act(on group: AppGroup, force: Bool) -> TerminationOutcome {
    let outcome = decide(group: group, force: force)
    Self.log.info(
      "quit \(group.name, privacy: .public) force=\(force) -> \(String(describing: outcome), privacy: .public)"
    )
    return outcome
  }

  private func decide(group: AppGroup, force: Bool) -> TerminationOutcome {
    if let app = runningApplication(group.representativePID) {
      let accepted = force ? app.forceTerminate() : app.terminate()
      return accepted ? .requestedAppQuit : .appRefused
    }
    let pid = group.representativePID
    guard let rowIdentity = group.children
      .first(where: { $0.snapshot.pid == pid })?.snapshot.startIdentity
    else { return .processGone }
    guard let liveIdentity = currentStartIdentity(pid) else {
      return .processGone
    }
    guard liveIdentity == rowIdentity else { return .staleIdentity }
    errno = 0
    let result = sendSignal(pid, force ? SIGKILL : SIGTERM)
    return result == 0 ? .signaled : .signalFailed(errno: errno)
  }
}
