# Popover Quit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Quit an app from its popover row, gracefully by default, with the affordance existing only in builds the OS actually allows to terminate processes.

**Architecture:** A launch-time capability check (`SecTaskCopyValueForEntitlement` on our own signature) gates everything. `ProcessTerminator` (@MainActor, injected OS primitives) maps app groups to `NSRunningApplication.terminate()/forceTerminate()` and standalone groups to SIGTERM/SIGKILL behind a `startIdentity` revalidation. `MonitorStore` exposes `canTerminate` plus `quit`/`forceQuit` and schedules a refresh as the only feedback. Both popover skins share one hover-confirm affordance view. The Direct (unsandboxed) build is an xcconfig overlay on Release; no pbxproj configuration changes.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, Swift Testing (`@Test`/`#expect`), sysctl/libproc, Security framework, xcodebuild.

**Spec:** `docs/superpowers/specs/2026-07-26-popover-quit-design.md`. Spike evidence: `Evidence/termination-spike/`.

## Global Constraints

- macOS 14.0 deployment target, Swift 6 strict concurrency, warnings as errors. Zero dependencies, no network.
- The sandboxed (Mac App Store) build must render byte-identical popover UI to today. Every quit affordance is absent when `canTerminate` is false.
- Popover ideal height must never depend on list content OR on capability. `PopoverLayoutTests` invariants must keep passing.
- Row height must not change on hover or confirm states (no layout shift; crossfade only).
- v1 acts on groups only, never child rows. No auto-escalation from Quit to Force Quit.
- Never signal a pid whose current `startIdentity` differs from the row snapshot's.
- Branding: no new imagery; telemetry stays undistorted. "Mac" and "Headroom" typeset equally.
- Tests run in the sandboxed TEST_HOST app: `xcodebuild test -project MacHeadroom.xcodeproj -scheme MacHeadroom -configuration Debug -destination 'platform=macOS,arch=arm64'`.
- Every new source file needs the four pbxproj edits (PBXBuildFile, PBXFileReference, owning group's `children`, target Sources phase) following the hand-rolled ID scheme.
- Commits follow the creating-git-commits skill: `type(scope): subject`, body, `Claude-Session:` trailer, no Co-Authored-By footer.

---

### Task 1: TerminationCapability

**Files:**
- Create: `MacHeadroom/App/ProcessTerminator.swift`
- Modify: `MacHeadroom.xcodeproj/project.pbxproj` (four entries)
- Create: `MacHeadroomTests/ProcessTerminatorTests.swift`
- Modify: `MacHeadroom.xcodeproj/project.pbxproj` (four more entries, test target)

**Interfaces:**
- Consumes: nothing.
- Produces: `enum TerminationCapability { case available, sandboxed }` with `static let current: TerminationCapability` and `var buildFlavorName: String` ("Direct" for available, "App Store" for sandboxed). Later tasks call `TerminationCapability.current`.

- [ ] **Step 1: Register the two new files in the pbxproj**

App sources use one ID prefix per group; find it by example, then clone all four entries per file. Run:

```bash
grep -n "MonitorStore.swift" MacHeadroom.xcodeproj/project.pbxproj
grep -n "MonitorStorePreferencesTests.swift" MacHeadroom.xcodeproj/project.pbxproj
```

Each grep shows the four locations (PBXBuildFile, PBXFileReference, group `children`, Sources phase). Duplicate each line for the new file, keeping the neighbor's ID prefix and bumping to the next unused hex value (e.g. if App files end at `…000C`, use `…000D`). `ProcessTerminator.swift` mirrors `MonitorStore.swift` (app target); `ProcessTerminatorTests.swift` mirrors `MonitorStorePreferencesTests.swift` (test target). Verify no duplicate IDs:

```bash
grep -oE '^[[:space:]]*[A-Z0-9]{24}' MacHeadroom.xcodeproj/project.pbxproj | sort | uniq -d
```

- [ ] **Step 2: Write the failing test**

`MacHeadroomTests/ProcessTerminatorTests.swift`:

```swift
import Testing

@testable import MacHeadroom

@Suite("Termination capability")
struct TerminationCapabilityTests {
  /// The test host is the sandboxed app itself, so the capability check
  /// must report sandboxed here. The available case is exercised by the
  /// Direct build's manual checklist; keep its code path trivial.
  @Test("Test host reports sandboxed")
  func testHostIsSandboxed() {
    #expect(TerminationCapability.current == .sandboxed)
  }

  @Test("Flavor names match distribution channels")
  func flavorNames() {
    #expect(TerminationCapability.sandboxed.buildFlavorName == "App Store")
    #expect(TerminationCapability.available.buildFlavorName == "Direct")
  }
}
```

- [ ] **Step 3: Run to verify failure**

```bash
xcodebuild test -project MacHeadroom.xcodeproj -scheme MacHeadroom -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:MacHeadroomTests/TerminationCapabilityTests 2>&1 | tail -20
```

Expected: build FAILS with "cannot find 'TerminationCapability' in scope".

- [ ] **Step 4: Implement**

`MacHeadroom/App/ProcessTerminator.swift`:

```swift
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
```

- [ ] **Step 5: Run to verify pass**

Same command as Step 3. Expected: PASS (both tests).

- [ ] **Step 6: Commit**

```bash
git add MacHeadroom/App/ProcessTerminator.swift MacHeadroomTests/ProcessTerminatorTests.swift MacHeadroom.xcodeproj/project.pbxproj
git commit  # feat(app): add TerminationCapability sandbox self-check — body + Claude-Session trailer per creating-git-commits
```

---

### Task 2: Single-pid identity revalidation

**Files:**
- Modify: `MacHeadroom/Sampling/ProcessTableSampler.swift`
- Test: `MacHeadroomTests/ProcessTerminatorTests.swift` (add a suite)

**Interfaces:**
- Consumes: existing `ProcessIdentity(kinfo_proc)` initializer and its `startIdentity` format `"sec:usec"`.
- Produces: `static func startIdentity(of pid: Int32) -> String?` on `ProcessTableSampler`. Returns nil when the pid is gone or unreadable. Task 3 injects this as the identity fetcher.

- [ ] **Step 1: Write the failing test**

Append to `ProcessTerminatorTests.swift`:

```swift
@Suite("Single-pid identity")
struct SinglePidIdentityTests {
  @Test("Own pid resolves and matches the full-table identity")
  func ownPidMatchesTable() {
    let pid = ProcessInfo.processInfo.processIdentifier
    let single = ProcessTableSampler.startIdentity(of: pid)
    let table = ProcessTableSampler.sampleReachableProcesses()
      .first { $0.pid == pid }?.startIdentity
    #expect(single != nil)
    #expect(single == table)
  }

  @Test("A dead pid returns nil")
  func deadPidReturnsNil() {
    // PID_MAX on macOS is 99998; a just-above-range pid can't exist.
    #expect(ProcessTableSampler.startIdentity(of: 99_999) == nil)
  }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
xcodebuild test -project MacHeadroom.xcodeproj -scheme MacHeadroom -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:MacHeadroomTests/SinglePidIdentityTests 2>&1 | tail -20
```

Expected: build FAILS, "type 'ProcessTableSampler' has no member 'startIdentity'".

- [ ] **Step 3: Implement**

Add to `ProcessTableSampler` (public section, above `enumerateProcesses`):

```swift
  /// Re-reads one pid's start-time identity immediately before a signal
  /// is sent. Rows can be a full sampling interval stale; a reused pid
  /// must never be signaled. Nil means the pid is gone or unreadable.
  static func startIdentity(of pid: Int32) -> String? {
    var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.size
    let result = mib.withUnsafeMutableBufferPointer { pointer in
      sysctl(pointer.baseAddress, UInt32(pointer.count), &info, &size, nil, 0)
    }
    guard result == 0, size == MemoryLayout<kinfo_proc>.size,
      info.kp_proc.p_pid == pid
    else { return nil }
    return ProcessIdentity(info).startIdentity
  }
```

Note: `KERN_PROC_PID` for a vanished pid returns success with `size == 0` on some releases and failure on others; the `size` and pid-echo guards cover both.

- [ ] **Step 4: Run to verify pass**

Same command as Step 2. Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add MacHeadroom/Sampling/ProcessTableSampler.swift MacHeadroomTests/ProcessTerminatorTests.swift
git commit  # feat(sampling): add single-pid startIdentity revalidation
```

---

### Task 3: ProcessTerminator service

**Files:**
- Modify: `MacHeadroom/App/ProcessTerminator.swift`
- Test: `MacHeadroomTests/ProcessTerminatorTests.swift` (add a suite)

**Interfaces:**
- Consumes: `AppGroup` (`representativePID`, `children[].snapshot.startIdentity`), `TerminationCapability`, `ProcessTableSampler.startIdentity(of:)`.
- Produces, used by Task 4:

```swift
enum TerminationOutcome: Sendable, Equatable {
  case requestedAppQuit      // NSRunningApplication path accepted the request
  case appRefused            // terminate()/forceTerminate() returned false
  case signaled              // kill() returned 0
  case signalFailed(errno: Int32)
  case staleIdentity         // pid's startIdentity changed; nothing sent
  case processGone           // pid vanished; nothing sent
}

@MainActor
struct ProcessTerminator {
  var runningApplication: (Int32) -> RunningAppHandle?
  var currentStartIdentity: (Int32) -> String?
  var sendSignal: (Int32, Int32) -> Int32
  static func live() -> ProcessTerminator
  func quit(_ group: AppGroup) -> TerminationOutcome
  func forceQuit(_ group: AppGroup) -> TerminationOutcome
}

/// Thin seam over NSRunningApplication so tests can fake the app path.
@MainActor
struct RunningAppHandle {
  var terminate: () -> Bool
  var forceTerminate: () -> Bool
}
```

- [ ] **Step 1: Write the failing tests**

Append to `ProcessTerminatorTests.swift` (file already imports Testing and MacHeadroom; add `import AppKit` at top if missing):

```swift
@Suite("ProcessTerminator")
@MainActor
struct ProcessTerminatorSuite {
  static func group(pid: Int32, identity: String) -> AppGroup {
    let snapshot = ProcessSnapshot(
      pid: pid, parentPID: 1, userID: 501, name: "victim",
      startIdentity: identity, cpuTimeTicks: 0, residentBytes: 1)
    return AppGroup(
      groupKey: "victim", name: "victim", bundleIdentifier: nil,
      representativePID: pid,
      cpuPercent: nil, memoryBytes: 1,
      children: [ProcessMeasurement(snapshot: snapshot, cpuPercent: nil)])
  }

  @Test("App groups quit via the app handle, not signals")
  func appPathUsesHandle() {
    var terminated = false
    var signals: [Int32] = []
    let terminator = ProcessTerminator(
      runningApplication: { _ in
        RunningAppHandle(
          terminate: { terminated = true; return true },
          forceTerminate: { false })
      },
      currentStartIdentity: { _ in "1:1" },
      sendSignal: { _, sig in signals.append(sig); return 0 })
    let outcome = terminator.quit(Self.group(pid: 500, identity: "1:1"))
    #expect(outcome == .requestedAppQuit)
    #expect(terminated)
    #expect(signals.isEmpty)
  }

  @Test("Force quit on an app group calls forceTerminate")
  func appForcePath() {
    var forced = false
    let terminator = ProcessTerminator(
      runningApplication: { _ in
        RunningAppHandle(
          terminate: { false },
          forceTerminate: { forced = true; return true })
      },
      currentStartIdentity: { _ in "1:1" },
      sendSignal: { _, _ in 0 })
    let outcome = terminator.forceQuit(Self.group(pid: 500, identity: "1:1"))
    #expect(outcome == .requestedAppQuit)
    #expect(forced)
  }

  @Test("Standalone quit sends SIGTERM only when identity matches")
  func standaloneMatchSendsTerm() {
    var sent: [(Int32, Int32)] = []
    let terminator = ProcessTerminator(
      runningApplication: { _ in nil },
      currentStartIdentity: { _ in "7:70" },
      sendSignal: { pid, sig in sent.append((pid, sig)); return 0 })
    let outcome = terminator.quit(Self.group(pid: 42, identity: "7:70"))
    #expect(outcome == .signaled)
    #expect(sent.count == 1)
    #expect(sent[0].0 == 42)
    #expect(sent[0].1 == SIGTERM)
  }

  @Test("Standalone force quit sends SIGKILL")
  func standaloneForceSendsKill() {
    var sent: [Int32] = []
    let terminator = ProcessTerminator(
      runningApplication: { _ in nil },
      currentStartIdentity: { _ in "7:70" },
      sendSignal: { _, sig in sent.append(sig); return 0 })
    _ = terminator.forceQuit(Self.group(pid: 42, identity: "7:70"))
    #expect(sent == [SIGKILL])
  }

  @Test("Identity mismatch aborts without signaling")
  func staleIdentityAborts() {
    var signalCount = 0
    let terminator = ProcessTerminator(
      runningApplication: { _ in nil },
      currentStartIdentity: { _ in "9:99" },
      sendSignal: { _, _ in signalCount += 1; return 0 })
    let outcome = terminator.quit(Self.group(pid: 42, identity: "7:70"))
    #expect(outcome == .staleIdentity)
    #expect(signalCount == 0)
  }

  @Test("Vanished pid aborts without signaling")
  func vanishedPidAborts() {
    var signalCount = 0
    let terminator = ProcessTerminator(
      runningApplication: { _ in nil },
      currentStartIdentity: { _ in nil },
      sendSignal: { _, _ in signalCount += 1; return 0 })
    let outcome = terminator.quit(Self.group(pid: 42, identity: "7:70"))
    #expect(outcome == .processGone)
    #expect(signalCount == 0)
  }

  @Test("Signal failure reports errno")
  func signalFailureReportsErrno() {
    let terminator = ProcessTerminator(
      runningApplication: { _ in nil },
      currentStartIdentity: { _ in "7:70" },
      sendSignal: { _, _ in errno = EPERM; return -1 })
    let outcome = terminator.quit(Self.group(pid: 42, identity: "7:70"))
    #expect(outcome == .signalFailed(errno: EPERM))
  }

  @Test("App refusal is reported")
  func appRefusalReported() {
    let terminator = ProcessTerminator(
      runningApplication: { _ in
        RunningAppHandle(terminate: { false }, forceTerminate: { false })
      },
      currentStartIdentity: { _ in "1:1" },
      sendSignal: { _, _ in 0 })
    #expect(terminator.quit(Self.group(pid: 500, identity: "1:1")) == .appRefused)
  }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
xcodebuild test -project MacHeadroom.xcodeproj -scheme MacHeadroom -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:MacHeadroomTests/ProcessTerminatorSuite 2>&1 | tail -20
```

Expected: build FAILS, "cannot find 'ProcessTerminator' in scope".

- [ ] **Step 3: Implement**

Append to `MacHeadroom/App/ProcessTerminator.swift`:

```swift
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
```

- [ ] **Step 4: Run to verify pass**

Same command as Step 2. Expected: PASS (all eight tests).

- [ ] **Step 5: Commit**

```bash
git add MacHeadroom/App/ProcessTerminator.swift MacHeadroomTests/ProcessTerminatorTests.swift
git commit  # feat(app): add ProcessTerminator with identity-guarded signal path
```

---

### Task 4: MonitorStore integration

**Files:**
- Modify: `MacHeadroom/App/MonitorStore.swift`
- Test: `MacHeadroomTests/MonitorStorePreferencesTests.swift` (add a suite or tests alongside existing style)

**Interfaces:**
- Consumes: `ProcessTerminator`, `TerminationCapability`.
- Produces, used by Tasks 5 and 6:
  - `MonitorStore.canTerminate: Bool` (true only when capability is `.available`)
  - `func quit(_ group: AppGroup)` and `func forceQuit(_ group: AppGroup)` (@MainActor, non-async; they fire the terminator and schedule a refresh)
  - `MonitorStore.preview(...)` gains `canTerminate: Bool = false`.

- [ ] **Step 1: Write the failing tests**

Add to `MonitorStorePreferencesTests.swift` (match the file's existing fixture style for constructing stores with a scratch `UserDefaults` suite; reuse its helper if one exists):

```swift
@Suite("Store termination gating")
@MainActor
struct StoreTerminationTests {
  static func makeStore(
    capability: TerminationCapability,
    terminator: ProcessTerminator
  ) -> MonitorStore {
    let suiteName = "com.vinnycarpenter.MacHeadroom.termination-tests"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return MonitorStore(
      defaults: defaults, capability: capability, terminator: terminator)
  }

  static func someGroup() -> AppGroup {
    let snapshot = ProcessSnapshot(
      pid: 77, parentPID: 1, userID: 501, name: "victim",
      startIdentity: "1:1", cpuTimeTicks: 0, residentBytes: 1)
    return AppGroup(
      groupKey: "victim", name: "victim", bundleIdentifier: nil,
      representativePID: 77, cpuPercent: nil, memoryBytes: 1,
      children: [ProcessMeasurement(snapshot: snapshot, cpuPercent: nil)])
  }

  @Test("Sandboxed store never invokes the terminator")
  func sandboxedStoreNoOps() {
    var calls = 0
    let terminator = ProcessTerminator(
      runningApplication: { _ in nil },
      currentStartIdentity: { _ in calls += 1; return "1:1" },
      sendSignal: { _, _ in calls += 1; return 0 })
    let store = Self.makeStore(capability: .sandboxed, terminator: terminator)
    #expect(store.canTerminate == false)
    store.quit(Self.someGroup())
    store.forceQuit(Self.someGroup())
    #expect(calls == 0)
  }

  @Test("Capable store routes quit and force quit to the terminator")
  func capableStoreRoutes() {
    var signals: [Int32] = []
    let terminator = ProcessTerminator(
      runningApplication: { _ in nil },
      currentStartIdentity: { _ in "1:1" },
      sendSignal: { _, sig in signals.append(sig); return 0 })
    let store = Self.makeStore(capability: .available, terminator: terminator)
    #expect(store.canTerminate == true)
    store.quit(Self.someGroup())
    store.forceQuit(Self.someGroup())
    #expect(signals == [SIGTERM, SIGKILL])
  }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
xcodebuild test -project MacHeadroom.xcodeproj -scheme MacHeadroom -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:MacHeadroomTests/StoreTerminationTests 2>&1 | tail -20
```

Expected: build FAILS, "extra arguments 'capability:terminator:' in call".

- [ ] **Step 3: Implement**

In `MonitorStore.swift`:

1. Add stored properties near `private let sampler`:

```swift
  let canTerminate: Bool
  private let terminator: ProcessTerminator
```

2. Extend `init` (keep existing defaults):

```swift
  init(
    sampler: SamplerService = SamplerService(),
    defaults: UserDefaults = .standard,
    capability: TerminationCapability = .current,
    terminator: ProcessTerminator = .live()
  ) {
    self.canTerminate = capability == .available
    self.terminator = terminator
    ...existing body unchanged...
  }
```

3. Add actions after `refreshNow()`:

```swift
  /// Termination feedback is the next sample: the row disappearing (or
  /// not) tells the truth better than a result state machine would.
  func quit(_ group: AppGroup) {
    performTermination { terminator.quit(group) }
  }

  func forceQuit(_ group: AppGroup) {
    performTermination { terminator.forceQuit(group) }
  }

  private func performTermination(_ action: () -> TerminationOutcome) {
    guard canTerminate else { return }
    _ = action()
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(1))
      await self?.refreshNow()
    }
  }
```

4. In the `preview(...)` factory, add parameter `canTerminate: Bool = false` and pass a recording-free terminator so previews stay inert:

```swift
    let store = MonitorStore(
      defaults: defaults,
      capability: canTerminate ? .available : .sandboxed,
      terminator: ProcessTerminator(
        runningApplication: { _ in nil },
        currentStartIdentity: { _ in nil },
        sendSignal: { _, _ in 0 }))
```

- [ ] **Step 4: Run to verify pass, plus the full suite**

Run the Step 2 command, then the whole suite (no `-only-testing`). Expected: all green; existing `MonitorStorePreferencesTests` and `PopoverLayoutTests` unaffected.

- [ ] **Step 5: Commit**

```bash
git add MacHeadroom/App/MonitorStore.swift MacHeadroomTests/MonitorStorePreferencesTests.swift
git commit  # feat(app): gate MonitorStore quit actions on termination capability
```

### Task 5: Quit affordance in the classic skin

**Files:**
- Create: `MacHeadroom/UI/QuitAffordanceView.swift` (four pbxproj entries, H-series IDs, mirror `MaxHeadroomPopoverView.swift`'s four lines)
- Modify: `MacHeadroom/UI/GroupRowView.swift`, `MacHeadroom/UI/PopoverView.swift`, `MacHeadroom/UI/PreviewFixtures.swift`
- Test: `MacHeadroomTests/PopoverLayoutTests.swift`

**Interfaces:**
- Consumes: `MonitorStore.canTerminate`, `store.quit(_:)`, `store.forceQuit(_:)` from Task 4.
- Produces: `QuitAffordanceView<Value: View>` (below) and `GroupRowView(group:metric:maxValue:store:)` — Task 6 reuses `QuitAffordanceView` unchanged. `PreviewFixtures.makeStore` gains `canTerminate: Bool = false`.

- [ ] **Step 1: Write the failing layout test**

Append to `PopoverLayoutTests.swift`:

```swift
  /// The affordance replaces the value text only under hover, so its
  /// presence in the hierarchy must never move layout: capability on and
  /// off must produce identical intrinsic sizes.
  @Test("Quit capability does not change classic popover size")
  @MainActor
  func classicCapabilityDoesNotChangeSize() {
    let gatedOff = PreviewFixtures.makeStore(usesPorcelainAppearance: false)
    let gatedOn = PreviewFixtures.makeStore(
      usesPorcelainAppearance: false, canTerminate: true)

    let offSize = NSHostingView(
      rootView: PopoverView(store: gatedOff)
    ).intrinsicContentSize
    let onSize = NSHostingView(
      rootView: PopoverView(store: gatedOn)
    ).intrinsicContentSize

    #expect(offSize == onSize)
  }
```

- [ ] **Step 2: Run to verify failure**

```bash
xcodebuild test -project MacHeadroom.xcodeproj -scheme MacHeadroom -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:MacHeadroomTests/PopoverLayoutTests 2>&1 | tail -20
```

Expected: build FAILS, "extra argument 'canTerminate' in call".

- [ ] **Step 3: Implement**

`MacHeadroom/UI/QuitAffordanceView.swift` (new file; register in pbxproj first, same four-edit recipe as Task 1):

```swift
import SwiftUI

/// Hover-revealed quit control shared by both skins. Renders the row's
/// value text; hover crossfades it to an ✕; a first click arms an inline
/// "Quit?" confirm; a second click quits. Hover exit or four seconds
/// disarms. The value keeps its frame (opacity swap, never removal), so
/// row height and width cannot shift.
struct QuitAffordanceView<Value: View>: View {
  let group: AppGroup
  let store: MonitorStore
  let accent: Color
  let secondary: Color
  @ViewBuilder let value: () -> Value

  @State private var isHovering = false
  @State private var isConfirming = false
  @State private var disarmTask: Task<Void, Never>?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var showsControls: Bool {
    store.canTerminate && (isHovering || isConfirming)
  }

  var body: some View {
    ZStack(alignment: .trailing) {
      value().opacity(showsControls ? 0 : 1)
      if showsControls {
        controls
      }
    }
    .onHover { hovering in
      guard store.canTerminate else { return }
      withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
        isHovering = hovering
        if !hovering { disarm() }
      }
    }
  }

  @ViewBuilder
  private var controls: some View {
    if isConfirming {
      Button {
        disarm()
        store.quit(group)
      } label: {
        Text("Quit?")
          .font(.callout.weight(.semibold))
          .foregroundStyle(accent)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Confirm quit \(group.name)")
    } else {
      Button {
        isConfirming = true
        disarmTask = Task {
          try? await Task.sleep(for: .seconds(4))
          if !Task.isCancelled { isConfirming = false }
        }
      } label: {
        Image(systemName: "xmark.circle")
          .foregroundStyle(secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Quit \(group.name)")
    }
  }

  private func disarm() {
    disarmTask?.cancel()
    disarmTask = nil
    isConfirming = false
  }
}

extension View {
  /// Row-level quit context menu and VoiceOver actions. Applied only
  /// when the store can terminate, so the sandboxed build's hierarchy
  /// is untouched.
  @ViewBuilder
  func quitContextMenu(for group: AppGroup, store: MonitorStore) -> some View {
    if store.canTerminate {
      self
        .contextMenu {
          Button("Quit \(group.name)") { store.quit(group) }
          Button("Force Quit \(group.name)", role: .destructive) {
            store.forceQuit(group)
          }
        }
        .accessibilityAction(named: "Quit") { store.quit(group) }
        .accessibilityAction(named: "Force Quit") { store.forceQuit(group) }
    } else {
      self
    }
  }
}
```

`GroupRowView.swift` changes:

1. Add `let store: MonitorStore` after `let group: AppGroup`.
2. Wrap the existing value text (the `Text(ValueFormatting.value(metric, for: group))` block, keeping its modifiers inside the closure):

```swift
        QuitAffordanceView(
          group: group, store: store,
          accent: .accentColor, secondary: .secondary
        ) {
          Text(ValueFormatting.value(metric, for: group))
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
        }
```

3. Append `.quitContextMenu(for: group, store: store)` to the row's outer `VStack`, after `.help(...)`.

`PopoverView.swift`: pass the store through — `GroupRowView(group: group, metric: selectedMetric, maxValue: maxValue, store: store)`.

`PreviewFixtures.swift`: thread the flag through to the preview factory. Change `makeStore` to accept `canTerminate: Bool = false` and forward it to `MonitorStore.preview(..., canTerminate: canTerminate)` (parameter added in Task 4).

- [ ] **Step 4: Run to verify pass, then the full suite**

Step 2 command first, then the whole suite without `-only-testing`. Expected: all green, including both pre-existing height-invariance tests.

- [ ] **Step 5: Commit**

```bash
git add MacHeadroom/UI/QuitAffordanceView.swift MacHeadroom/UI/GroupRowView.swift MacHeadroom/UI/PopoverView.swift MacHeadroom/UI/PreviewFixtures.swift MacHeadroomTests/PopoverLayoutTests.swift MacHeadroom.xcodeproj/project.pbxproj
git commit  # feat(ui): add hover quit affordance to classic popover rows
```

---

### Task 6: Quit affordance in the Porcelain skin

**Files:**
- Modify: `MacHeadroom/UI/MaxHeadroomPopoverView.swift`
- Test: `MacHeadroomTests/PopoverLayoutTests.swift`

**Interfaces:**
- Consumes: `QuitAffordanceView`, `.quitContextMenu(for:store:)`, `PreviewFixtures.makeStore(canTerminate:)` from Task 5.
- Produces: nothing new; `PorcelainGroupRowView` gains a `store` property.

**Structural constraint:** `PorcelainGroupRowView.rowControl` wraps the whole row in a `Button` when `processCount > 1`. A quit `Button` nested inside that label would fight it for clicks. Restructure so the value area sits outside the expand button:

- [ ] **Step 1: Write the failing layout test**

Append to `PopoverLayoutTests.swift`:

```swift
  @Test("Quit capability does not change Porcelain popover size")
  @MainActor
  func porcelainCapabilityDoesNotChangeSize() {
    let gatedOff = PreviewFixtures.makeStore()
    let gatedOn = PreviewFixtures.makeStore(canTerminate: true)

    let offSize = NSHostingView(
      rootView: PopoverView(store: gatedOff)
    ).intrinsicContentSize
    let onSize = NSHostingView(
      rootView: PopoverView(store: gatedOn)
    ).intrinsicContentSize

    #expect(offSize == onSize)
  }
```

- [ ] **Step 2: Run to verify failure**

Layout-tests command from Task 5 Step 2. This test passes trivially until the Porcelain row changes land, so the meaningful failure here is compile-time only if Step 3 introduces one; run it anyway to lock the invariant in before restructuring.

- [ ] **Step 3: Implement**

In `MaxHeadroomPopoverView.swift`:

1. Add `let store: MonitorStore` to `PorcelainGroupRowView` and pass it from the `ForEach` in `PorcelainPopoverView` (which already holds `store`).
2. Restructure `rowContent`'s top `HStack`: keep icon, the two-line title `VStack`, and the `Spacer` as `rowCore`. When `processCount > 1`, `rowControl` wraps only `rowCore` in the expand `Button`, and the chevron becomes its own small `Button` toggling the same `isExpanded` (mirroring `GroupRowView`'s chevron pattern, same rotation and animation). The value `Text` moves between them, outside any button, wrapped:

```swift
        QuitAffordanceView(
          group: group, store: store,
          accent: palette.accent, secondary: palette.textSecondary
        ) {
          Text(ValueFormatting.value(metric, for: group))
            .font(.system(size: 15, weight: isTopConsumer ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(isTopConsumer ? palette.textPrimary : palette.textSecondary)
        }
```

3. Keep the single-process branch as plain `rowContent` (no expand button), same wrapper around its value text.
4. Append `.quitContextMenu(for: group, store: store)` to the row container in `body`, after `rowControl`'s modifiers.
5. Preserve the existing accessibility labels, values, and hints on the expand control; the padding, capsule indicator, `contentShape`, and `help` stay exactly as they are so the skin looks unchanged when idle.

- [ ] **Step 4: Run the full suite**

Whole suite, no `-only-testing`. Expected: all green, including the two capability-parity tests and both original height tests.

- [ ] **Step 5: Commit**

```bash
git add MacHeadroom/UI/MaxHeadroomPopoverView.swift MacHeadroomTests/PopoverLayoutTests.swift
git commit  # feat(ui): add quit affordance to Porcelain rows without layout shift
```

---

### Task 7: Direct build path, About flavor line, docs

**Files:**
- Create: `Configuration/Direct.xcconfig`, `MacHeadroom/MacHeadroomDirect.entitlements`, `Scripts/build-direct.sh`
- Modify: `MacHeadroom/UI/AboutView.swift`, `README.md`, `CLAUDE.md`

**Interfaces:**
- Consumes: `TerminationCapability.current.buildFlavorName` from Task 1.
- Produces: a runnable unsandboxed Direct build and the documentation trail.

- [ ] **Step 1: Create the overlay xcconfig and empty entitlements**

`Configuration/Direct.xcconfig`:

```
// Direct-download (Developer ID) overlay. Applied at invocation time via
// `xcodebuild -xcconfig`; the project's own configurations never change.
// No sandbox: the popover quit feature exists only here. Hardened runtime
// stays on from Shared.xcconfig for notarization.
#include "Release.xcconfig"

ENABLE_APP_SANDBOX = NO
CODE_SIGN_ENTITLEMENTS = MacHeadroom/MacHeadroomDirect.entitlements
```

`MacHeadroom/MacHeadroomDirect.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

- [ ] **Step 2: Create the build script**

`Scripts/build-direct.sh` (then `chmod +x Scripts/build-direct.sh`):

```bash
#!/bin/zsh
# Build the unsandboxed Direct flavor and prove it is unsandboxed.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -project MacHeadroom.xcodeproj -scheme MacHeadroom \
  -configuration Release \
  -xcconfig Configuration/Direct.xcconfig \
  -derivedDataPath build/direct build

app="build/direct/Build/Products/Release/Mac Headroom.app"
if codesign -d --entitlements - "$app" 2>/dev/null | grep -q "app-sandbox"; then
  echo "FAIL: Direct build still carries the sandbox entitlement" >&2
  exit 1
fi
echo "OK: unsandboxed Direct build at $app"
```

Run it. Expected output ends with `OK: unsandboxed Direct build at …`. (`build/` is already outside version control; confirm with `git status --short` showing no `build/` entries — if it appears, add `build/` to `.gitignore` in this task.)

- [ ] **Step 3: Add the About flavor line**

In `AboutView.swift`, find the existing version rows (they read `MARKETING_VERSION`/build from the bundle via `AppIdentity`). Add one row in the same visual style, e.g. alongside the version `LabeledContent`/`Text` pair:

```swift
Text("Build: \(TerminationCapability.current.buildFlavorName)")
```

styled identically to the neighboring secondary text. In the sandboxed dev build it reads "Build: App Store".

- [ ] **Step 4: Run the full suite**

Whole suite. Expected: green (Task 1's flavor tests already cover the strings; the About change is presentation only).

- [ ] **Step 5: Document**

`CLAUDE.md`, "Hard-won constraints" section, add one bullet:

```markdown
- **Termination is capability-gated.** The App Sandbox denies every way
  to quit or kill another process (measured July 26, 2026; see the
  SANDBOX_NOTES.md addendum). Quit UI must stay behind
  `MonitorStore.canTerminate` and only the unsandboxed Direct build
  (`Scripts/build-direct.sh`) has it. Do not add termination UI to the
  Mac App Store build.
```

`README.md`: add a short "Build flavors" section naming the two flavors, the script, and that the quit feature exists only in Direct.

- [ ] **Step 6: Manual verification checklist (Vinny)**

The sandboxed test host cannot deliver real signals, so the feature's end-to-end proof is manual on the Direct build:

1. `Scripts/build-direct.sh && open "build/direct/Build/Products/Release/Mac Headroom.app"` (SingleInstanceGuard retires any running copy; the icon may land in Control Center's overflow on a crowded menu bar).
2. About tab reads "Build: Direct".
3. `open -a TextEdit`, drive it near the top of the CPU list (or find it under Memory), hover its row: ✕ appears without the row moving; click, "Quit?" appears; click again; TextEdit quits and the row drops on the next refresh.
4. Right-click another sacrificial row: Quit and Force Quit menu items appear; Force Quit kills without a save prompt.
5. Confirm hover-out disarms the confirm state.
6. Launch the normal Debug build; hover shows nothing, no context menu items, About reads "Build: App Store".

- [ ] **Step 7: Commit**

```bash
git add Configuration/Direct.xcconfig MacHeadroom/MacHeadroomDirect.entitlements Scripts/build-direct.sh MacHeadroom/UI/AboutView.swift README.md CLAUDE.md
git commit  # feat(release): add unsandboxed Direct build flavor with quit feature
```

---

## Plan self-review notes

- Spec coverage: capability gate (T1), identity revalidation (T2), terminator semantics and os_log (T3), store actions and delayed refresh (T4), classic-skin hover/confirm/context menu/VoiceOver/Reduce Motion (T5), Porcelain parity (T6), Direct build, About flavor, SANDBOX_NOTES pointer docs (T7). The SANDBOX_NOTES addendum itself already landed with the spec commit.
- Deviation from spec wording, deliberate: "Release-Direct build configuration" is realized as an invocation-time xcconfig overlay plus script instead of pbxproj configuration surgery. Same semantics (MAS Release untouched, unsandboxed + hardened runtime), far less risk in a hand-rolled pbxproj. Also, Escape-to-revert became hover-out/timeout disarm: Escape closes a MenuBarExtra popover at the system level before a row could see it.
- Out of scope per spec: per-child kill, auto-escalation, MAS affordances, notarization pipeline, updates, DTS filing.

