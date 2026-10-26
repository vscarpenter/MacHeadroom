# Port actions, memory pressure, and CPU alerts implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship System Headroom 1.5.0 (17): whole-row hit testing on port rows, Open and Copy actions on port rows, memory pressure and swap in the popover header, and sustained CPU notifications.

**Architecture:** Each feature reuses an existing boundary. Port actions extend the context menu the force-quit work attached. Pressure and swap ride `SystemSummary` through `SamplerService.tick`. Alerts put a pure `CPUAlertTracker` in `Grouping/` between `MonitorStore.refreshNow` and a `UNUserNotificationCenter` wrapper behind an `AlertDelivery` protocol.

**Tech Stack:** Swift 6 (language mode 6.0, strict concurrency complete, warnings as errors), SwiftUI, Swift Testing, hosted test bundle inside the sandboxed app. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-26-port-actions-pressure-alerts-design.md`

## Global constraints

- Popover intrinsic size must not depend on content or capability. Every header addition renders in every state. `PopoverLayoutTests` pins equal size.
- No termination UI in the App Store build. Quit items stay behind `store.canTerminate`.
- Sandbox reads are measured before UI depends on them. The live test runs before the badge task.
- Zero dependencies, no network. UserNotifications, NSWorkspace, and NSPasteboard only.
- New source files need four `project.pbxproj` edits each: PBXBuildFile, PBXFileReference, group `children`, target Sources phase. IDs: UI `H1…/H2…` next free `0F`, Grouping `F1…/F2…` next free `06`, App `G1…/G2…` next free `04`, tests `E1…/E2…` next free `13`. IDs are 24 hex characters: prefix, zeros, two-digit suffix.
- Shipped prose follows vinny-voice: no em dashes, no en dashes as dashes, no double hyphens in prose, sentences under 25 words.
- Commits: Conventional Commits with scope, Claude-Session trailer, one commit per task. Never `git add -A`.
- Test command: `xcodebuild test -project SystemHeadroom.xcodeproj -scheme SystemHeadroom -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:SystemHeadroomTests/<Suite>` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Four `PortsSamplerLiveTests` fail on this Mac regardless (pre-existing, see tasks/todo.md).

## Review focus

1. A row with four ports exactly: flat items, not submenus. Pinned in Task 2 (`usesSubmenus(portCount: 4) == false`).
2. The pressure sysctl returns a value outside 1, 2, 4 (a future macOS adds a level): badge shows Unknown, nothing traps. Pinned in Task 5 (`MemoryPressureLevel(rawPressure: 3) == nil`).
3. A group whose `cpuPercent` is nil (priming tick) must never become a candidate, or a nil-to-zero coercion would end episodes early. Pinned in Task 9 (`candidates(from:)` drops nil).
4. Switching the list convention mid-episode must not change the per-core figure the tracker sees. Pinned in Task 9 (`percentOfCore` under `.perCore` equals the raw percent, under `.machineCapacity` equals percent times cores).
5. Turning alerts off while the popover is open must not stop sampling. Pinned in Task 9 (prefs test "disabling alerts with the popover open keeps sampling").

---

### Task 0: Branch and commit the design docs

**Files:**
- Commit: `docs/superpowers/specs/2026-10-26-port-actions-pressure-alerts-design.md`, `docs/superpowers/plans/2026-10-26-port-actions-pressure-alerts.md`

- [ ] **Step 1: Cut the stacked branch**

```bash
git checkout -b feat/1.5.0-port-actions-pressure-alerts
```

Expected: branch created at `17b3f7f`.

- [ ] **Step 2: Mark the spec approved and commit both docs**

Change the spec's Status line to `Status: approved by Vinny on October 26, 2026.`

```bash
git add docs/superpowers/specs/2026-10-26-port-actions-pressure-alerts-design.md docs/superpowers/plans/2026-10-26-port-actions-pressure-alerts.md
git commit -m "docs(spec): add the 1.5.0 port actions, pressure, and alerts design"
```

### Task 1: Port rows answer the whole row (Part 0)

**Files:**
- Modify: `SystemHeadroom/UI/PortsPaneView.swift:79-81`
- Modify: `SystemHeadroom/UI/MaxHeadroomPopoverView.swift:656-658`

Trivial tier: one modifier, no logic. No unit test can observe hit testing without a window; the existing `PopoverLayoutTests` pin size.

- [ ] **Step 1: Add `.contentShape(Rectangle())` after `.frame(height:)` and before `.accessibilityElement` in both `labeledRow` properties**

- [ ] **Step 2: Run the layout suite**

Run: `-only-testing:SystemHeadroomTests/PopoverLayoutTests`
Expected: 8 tests pass.

- [ ] **Step 3: Commit**

```bash
git add SystemHeadroom/UI/PortsPaneView.swift SystemHeadroom/UI/MaxHeadroomPopoverView.swift
git commit -m "fix(ports): hit-test the whole port row"
```

### Task 2: Pure port action helpers

**Files:**
- Create: `SystemHeadroom/UI/PortRowActions.swift` (H…0F)
- Test: `SystemHeadroomTests/PortRowActionsTests.swift` (E…13)
- Modify: `SystemHeadroom.xcodeproj/project.pbxproj` (eight lines)

**Interfaces:**
- Produces: `enum PortRowActions` with `static func url(for port: ListeningPort) -> URL?`, `static func address(for port: ListeningPort) -> String`, `static func usesSubmenus(portCount: Int) -> Bool`, `static let flatItemLimit = 4`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import SystemHeadroom

@Suite("Port row actions")
struct PortRowActionsTests {
  @Test("TCP ports open as http localhost URLs")
  func tcpURL() {
    let port = ListeningPort(number: 3000, transport: .tcp)
    #expect(PortRowActions.url(for: port) == URL(string: "http://localhost:3000"))
  }

  @Test("UDP ports have no URL")
  func udpURL() {
    #expect(PortRowActions.url(for: ListeningPort(number: 5353, transport: .udp)) == nil)
  }

  @Test("Address copies as localhost and port, no locale grouping")
  func address() {
    #expect(PortRowActions.address(for: ListeningPort(number: 65000, transport: .tcp)) == "localhost:65000")
  }

  @Test("Submenus start above four ports", arguments: [(1, false), (4, false), (5, true), (7, true)])
  func submenuCutoff(count: Int, expected: Bool) {
    #expect(PortRowActions.usesSubmenus(portCount: count) == expected)
  }
}
```

- [ ] **Step 2: Add both files to the pbxproj, then run the suite to see it fail**

Run: `-only-testing:SystemHeadroomTests/PortRowActionsTests`
Expected: build fails, `PortRowActions` undefined.

- [ ] **Step 3: Implement `PortRowActions` in `SystemHeadroom/UI/PortRowActions.swift`**

Foundation only. Build the address with `String(port.number)` so the UInt16 never picks up grouping separators. `url(for:)` returns nil for `.udp`.

- [ ] **Step 4: Run the suite**

Expected: 6 tests pass (parameterized cases count individually).

- [ ] **Step 5: Commit**

```bash
git add SystemHeadroom/UI/PortRowActions.swift SystemHeadroomTests/PortRowActionsTests.swift SystemHeadroom.xcodeproj/project.pbxproj
git commit -m "feat(ports): add pure helpers for port row actions"
```

### Task 3: Shared port row menu with Open and Copy

**Files:**
- Create: `SystemHeadroom/UI/PortRowMenu.swift` (H…10)
- Modify: `SystemHeadroom/UI/QuitAffordanceView.swift:83-103`
- Modify: `SystemHeadroom/UI/PortsPaneView.swift` (`PortRowView`)
- Modify: `SystemHeadroom/UI/MaxHeadroomPopoverView.swift` (`PorcelainPortRowView`)
- Modify: `SystemHeadroom/UI/HelpView.swift:70-73`
- Modify: `SystemHeadroom.xcodeproj/project.pbxproj` (four lines)

**Interfaces:**
- Consumes: `PortRowActions` from Task 2.
- Produces: `struct QuitMenuItems: View { let group: AppGroup; let store: MonitorStore }` in QuitAffordanceView.swift. `struct PortActionHandler { let open: (URL) -> Void; let copy: (String) -> Void; static let live: PortActionHandler }` and `extension View { func portRowMenu(for group: PortGroup, store: MonitorStore, handler: PortActionHandler) -> some View }` in PortRowMenu.swift. Both row views gain `var handler: PortActionHandler = .live`.

- [ ] **Step 1: Extract `QuitMenuItems`**

Move the two `Button`s out of `quitContextMenu` into `QuitMenuItems.body`. `quitContextMenu` becomes `.contextMenu { QuitMenuItems(group: group, store: store) }` plus the two unchanged accessibility actions. `GroupRowView` does not change.

- [ ] **Step 2: Write `PortRowMenu.swift`**

`PortActionHandler.live`: `open` calls `NSWorkspace.shared.open(url)`; `copy` calls `NSPasteboard.general.clearContents()` then `setString(_, forType: .string)`.

`portRowMenu(for:store:handler:)` is a plain `func` returning `some View` (no `@ViewBuilder` branch, both editions get a menu):

- `.contextMenu { PortRowMenuItems(group:store:handler:) }`
- `.accessibilityActions { PortRowMenuItems(group:store:handler:) }`

`PortRowMenuItems` is a private `View`:

- `if store.canTerminate, let appGroup = group.appGroup { QuitMenuItems(group: appGroup, store: store); Divider() }`
- When `PortRowActions.usesSubmenus(portCount: group.ports.count)`: `Menu("Open in Browser") { openButtons }` and `Menu("Copy Address") { copyButtons }`. Otherwise `openButtons` then `copyButtons` flat.
- `openButtons`: `ForEach(group.ports.filter { PortRowActions.url(for: $0) != nil }, id: \.self)` producing `Button("Open \(PortRowActions.address(for: port))") { handler.open(url) }`.
- `copyButtons`: `ForEach(group.ports, id: \.self)` producing `Button("Copy \(PortRowActions.address(for: port))") { handler.copy(PortRowActions.address(for: port)) }`.

Inside `accessibilityActions`, a `Menu` is not an action. Use a `Bool` parameter `flattened` on `PortRowMenuItems` that skips the `Menu` wrappers; pass `true` from the accessibility branch. `Divider` inside `accessibilityActions` is ignored by VoiceOver, so it needs no guard.

- [ ] **Step 3: Replace `menuRow` in both row views**

Delete the `menuRow` property in `PortRowView` and `PorcelainPortRowView`. `body` becomes `labeledRow.portRowMenu(for: group, store: store, handler: handler).onHover { ... }`. Add `var handler: PortActionHandler = .live` after `let store`. Call sites in `PortsPaneView` and `PorcelainPopoverView` stay as they are.

- [ ] **Step 4: Add the Help fact**

After the "Ports" `HelpFact` in "Read the signal": title "Open or copy a port", detail "Control-click a Ports row to open localhost and that port in your browser, or to copy the address."

- [ ] **Step 5: Run the layout and visual suites**

Run: `-only-testing:SystemHeadroomTests/PopoverLayoutTests -only-testing:SystemHeadroomTests/PopoverVisualTests`
Expected: all pass. The four ports capability tests prove the menu does not move layout.

- [ ] **Step 6: Commit**

```bash
git add SystemHeadroom/UI/PortRowMenu.swift SystemHeadroom/UI/QuitAffordanceView.swift SystemHeadroom/UI/PortsPaneView.swift SystemHeadroom/UI/MaxHeadroomPopoverView.swift SystemHeadroom/UI/HelpView.swift SystemHeadroom.xcodeproj/project.pbxproj
git commit -m "feat(ports): add Open and Copy to port row menus"
```

### Task 4: Memory pressure and swap reads (Part 2, data)

**Files:**
- Modify: `SystemHeadroom/Sampling/HostSampler.swift`
- Modify: `SystemHeadroom/Sampling/MonitorTick.swift:6-10`
- Modify: `SystemHeadroom/Sampling/SamplerService.swift:81-99`
- Test: `SystemHeadroomTests/MemoryPressureLevelTests.swift` (E…14)
- Test: `SystemHeadroomTests/HostPressureLiveTests.swift` (E…15)
- Modify: `SystemHeadroom.xcodeproj/project.pbxproj` (eight lines, tests only)
- Maybe modify: `SANDBOX_NOTES.md` (only if the sandbox denies a read)

**Interfaces:**
- Produces, in HostSampler.swift: `enum MemoryPressureLevel: Sendable, Equatable { case normal, warning, critical; init?(rawPressure: Int32); var displayName: String }` ("Normal", "Warning", "Critical"). `struct HostSwapSnapshot: Sendable, Equatable { let usedBytes: UInt64; let totalBytes: UInt64 }`. `HostSampler.sampleMemoryPressure() -> MemoryPressureLevel?` and `HostSampler.sampleSwapUsage() -> HostSwapSnapshot?`.
- Produces, in MonitorTick.swift: `SystemSummary` gains `var memoryPressure: MemoryPressureLevel? = nil` and `var swapUsedBytes: UInt64? = nil` (vars with defaults so the memberwise init keeps every existing call site).

- [ ] **Step 1: Write the failing mapping tests**

```swift
@Suite("Memory pressure level")
struct MemoryPressureLevelTests {
  @Test("Raw sysctl levels map to the three states", arguments: [
    (Int32(1), MemoryPressureLevel.normal), (2, .warning), (4, .critical),
  ])
  func mapping(raw: Int32, expected: MemoryPressureLevel) {
    #expect(MemoryPressureLevel(rawPressure: raw) == expected)
  }

  @Test("Unknown raw levels map to nil", arguments: [Int32(0), 3, 5, -1])
  func unknown(raw: Int32) {
    #expect(MemoryPressureLevel(rawPressure: raw) == nil)
  }

  @Test("Display names")
  func displayNames() {
    #expect(MemoryPressureLevel.normal.displayName == "Normal")
    #expect(MemoryPressureLevel.warning.displayName == "Warning")
    #expect(MemoryPressureLevel.critical.displayName == "Critical")
  }
}
```

- [ ] **Step 2: Write the failing live tests (sandboxed host)**

```swift
@Suite("Host pressure live")
struct HostPressureLiveTests {
  @Test("Sandboxed pressure read returns a level")
  func pressure() throws {
    _ = try #require(HostSampler.sampleMemoryPressure())
  }

  @Test("Sandboxed swap read returns a snapshot within bounds")
  func swap() throws {
    let swap = try #require(HostSampler.sampleSwapUsage())
    #expect(swap.usedBytes <= swap.totalBytes)
  }

  @Test("Tick carries pressure and swap")
  func tickCarriesPressure() async throws {
    let tick = await SamplerService().tick(convention: .machineCapacity)
    #expect(tick.system.memoryPressure != nil)
    #expect(tick.system.swapUsedBytes != nil)
  }
}
```

- [ ] **Step 3: Add both test files to the pbxproj and run them**

Expected: build fails, `MemoryPressureLevel` undefined.

- [ ] **Step 4: Implement the reads**

`sampleMemoryPressure()`: `sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)` into an `Int32`; return nil on nonzero result or when `size != MemoryLayout<Int32>.size`; otherwise `MemoryPressureLevel(rawPressure: level)`.

`sampleSwapUsage()`: `sysctlbyname("vm.swapusage", &usage, &size, nil, 0)` into an `xsw_usage`; return nil on nonzero result; otherwise `HostSwapSnapshot(usedBytes: usage.xsu_used, totalBytes: usage.xsu_total)`.

`SamplerService.tick`: read both next to `hostMemory` and pass `memoryPressure:` and `swapUsedBytes: swap?.usedBytes` into `SystemSummary`.

- [ ] **Step 5: Run both suites**

Expected: all pass. If a live test fails with a denied read, keep the nil path, append a dated addendum to `SANDBOX_NOTES.md` with the exact errno and test log path, and note it in `tasks/implementation-notes.md`. The badge then shows Unknown for that field.

- [ ] **Step 6: Commit**

```bash
git add SystemHeadroom/Sampling/HostSampler.swift SystemHeadroom/Sampling/MonitorTick.swift SystemHeadroom/Sampling/SamplerService.swift SystemHeadroomTests/MemoryPressureLevelTests.swift SystemHeadroomTests/HostPressureLiveTests.swift SystemHeadroom.xcodeproj/project.pbxproj
git commit -m "feat(sampling): read memory pressure and swap each tick"
```

### Task 5: Memory pressure badge in both headers (Part 2, display)

**Files:**
- Create: `SystemHeadroom/UI/MemoryPressureBadge.swift` (H…11)
- Modify: `SystemHeadroom/UI/PopoverView.swift:61-70`
- Modify: `SystemHeadroom/UI/MaxHeadroomPopoverView.swift:128-131`
- Modify: `SystemHeadroom/UI/HelpView.swift` ("Read the signal")
- Modify: `SystemHeadroomTests/MemoryPressureLevelTests.swift` (badge text)
- Modify: `SystemHeadroomTests/PopoverLayoutTests.swift`
- Modify: `SystemHeadroom.xcodeproj/project.pbxproj` (four lines)

**Interfaces:**
- Consumes: `MemoryPressureLevel`, `SystemSummary.memoryPressure`, `SystemSummary.swapUsedBytes` from Task 4.
- Produces: `struct MemoryPressureBadge: View { let level: MemoryPressureLevel?; let swapUsedBytes: UInt64?; var secondaryColor: Color = .secondary }` with `static func levelText(_:) -> String` ("Unknown" for nil), `static func swapText(_:) -> String` ("Swap 1.2 GB" via `ValueFormatting.bytes`, "Swap —" for nil), `static func accessibilityLabel(level:swapUsedBytes:) -> String` ("Memory pressure normal, 1.2 GB of swap in use"; "Memory pressure unknown, swap unknown" when both nil), `static func color(for:) -> Color` (green, orange, red, gray).

- [ ] **Step 1: Write the failing text tests (append to `MemoryPressureLevelTests`)**

```swift
@Test("Badge text and accessibility label")
func badgeText() {
  #expect(MemoryPressureBadge.levelText(nil) == "Unknown")
  #expect(MemoryPressureBadge.levelText(.warning) == "Warning")
  #expect(MemoryPressureBadge.swapText(nil) == "Swap —")
  #expect(MemoryPressureBadge.swapText(1_200_000_000) == "Swap \(ValueFormatting.bytes(1_200_000_000))")
  #expect(
    MemoryPressureBadge.accessibilityLabel(level: .normal, swapUsedBytes: 1_200_000_000)
      == "Memory pressure normal, \(ValueFormatting.bytes(1_200_000_000)) of swap in use")
  #expect(
    MemoryPressureBadge.accessibilityLabel(level: nil, swapUsedBytes: nil)
      == "Memory pressure unknown, swap unknown")
}
```

- [ ] **Step 2: Write the failing layout tests (append to `PopoverLayoutTests`)**

Two tests, "Memory pressure state does not change classic popover size" and "... Porcelain popover size". Each builds two stores with `MonitorStore.preview(cpuGroups: [], memoryGroups: [], summary:, usesPorcelainAppearance:)`: one summary `SystemSummary(cpuPercent: nil, memoryUsedBytes: 0, memoryTotalBytes: 0)` and one `SystemSummary(cpuPercent: 34.2, memoryUsedBytes: 12_800_000_000, memoryTotalBytes: 36_000_000_000, memoryPressure: .critical, swapUsedBytes: 3_000_000_000)`. Assert `intrinsicContentSize` equal. Also assert the classic populated height is greater than the value today plus 10, to prove the third line rendered: measure the current classic height once before the change and pin `> current`.

- [ ] **Step 3: Run the two suites to see them fail**

Expected: `MemoryPressureBadge` undefined.

- [ ] **Step 4: Implement the badge**

`body`: `HStack(spacing: 6) { Circle().fill(Self.color(for: level)).frame(width: 8, height: 8); Text(Self.levelText(level)); Text(Self.swapText(swapUsedBytes)).foregroundStyle(secondaryColor) }` with `.accessibilityElement(children: .combine)` and `.accessibilityLabel(Self.accessibilityLabel(level:swapUsedBytes:))`. Font is the caller's.

- [ ] **Step 5: Place it in both headers**

Classic (`PopoverView.header`): after the caption `HStack`, add `MemoryPressureBadge(level: store.systemSummary.memoryPressure, swapUsedBytes: store.systemSummary.swapUsedBytes).font(.caption).foregroundStyle(.secondary)`.

Porcelain (`PorcelainPopoverView.header`): replace the bare picker with `VStack(alignment: .trailing, spacing: PorcelainSpacing.sm) { PorcelainMetricPicker(...).frame(width: 240); MemoryPressureBadge(level:, swapUsedBytes:, secondaryColor: palette.textSecondary).font(.system(size: 11)).foregroundStyle(palette.textSecondary) }`. Header frame stays 172.

- [ ] **Step 6: Add the Help fact**

In "Read the signal" after "Open or copy a port": title "Memory pressure and swap", detail "The light stays green while macOS has room. Yellow means it is compressing memory to keep up. Red means it is short on memory and apps may stall. Swap shows how much memory is parked on disk right now."

- [ ] **Step 7: Run the layout, visual, and pressure suites**

Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add SystemHeadroom/UI/MemoryPressureBadge.swift SystemHeadroom/UI/PopoverView.swift SystemHeadroom/UI/MaxHeadroomPopoverView.swift SystemHeadroom/UI/HelpView.swift SystemHeadroomTests/MemoryPressureLevelTests.swift SystemHeadroomTests/PopoverLayoutTests.swift SystemHeadroom.xcodeproj/project.pbxproj
git commit -m "feat(ui): show memory pressure and swap in the header"
```

### Task 6: Pure CPU alert tracker (Part 3, decision)

**Files:**
- Create: `SystemHeadroom/Grouping/CPUAlertTracker.swift` (F…06)
- Test: `SystemHeadroomTests/CPUAlertTrackerTests.swift` (E…16)
- Modify: `SystemHeadroom.xcodeproj/project.pbxproj` (eight lines)

**Interfaces:**
- Produces:

```swift
struct CPUAlertPolicy: Sendable, Equatable {
  let thresholdPercentOfCore: Int
  let sustainSeconds: Int
  var cooldownSeconds: Int = 300
  static func describe(sustainSeconds: Int) -> String  // "30 seconds", "1 minute", "2 minutes", "5 minutes"
}
struct CPUAlertCandidate: Sendable, Equatable { let groupKey: String; let name: String; let percentOfCore: Double }
struct CPUAlert: Sendable, Equatable {
  let groupKey: String; let name: String; let percentOfCore: Double; let policy: CPUAlertPolicy
  var title: String  // "Google Chrome at 180% CPU"
  var body: String   // "Above 90% of a core for 1 minute."
}
struct CPUAlertTracker: Sendable {
  init()
  mutating func observe(_ candidates: [CPUAlertCandidate], at now: Date, policy: CPUAlertPolicy) -> [CPUAlert]
}
```

`describe(sustainSeconds:)`: below 60 → "\(n) seconds"; otherwise minutes with "minute"/"minutes".

- [ ] **Step 1: Write the failing tests**

Fixture: `policy = CPUAlertPolicy(thresholdPercentOfCore: 90, sustainSeconds: 60)`, `chrome(_ pct: Double)` builds a candidate with key "com.google.Chrome", name "Google Chrome". `t0 = Date(timeIntervalSinceReferenceDate: 0)`, `at(_ s: Double)` adds seconds.

```swift
@Test("Below threshold never alerts")  // observe 50 at 0, 70 at 120 → both empty
@Test("Above threshold but shorter than sustain does not alert")  // 180 at 0, 180 at 59 → empty
@Test("Sustained above threshold alerts exactly once")  // 180 at 0, 180 at 60 → one alert; title "Google Chrome at 180% CPU", body "Above 90% of a core for 1 minute."
@Test("Still above after alerting does not repeat")  // continue 180 at 120, 180 at 400 → empty
@Test("Dropping below and re-crossing inside the cooldown stays quiet")  // alert at 60; 10 at 70; 180 at 80; 180 at 140 → empty (cooldown ends at 360)
@Test("After the cooldown a new episode alerts again")  // alert at 60; 10 at 70; 180 at 361; 180 at 421 → one alert
@Test("A group that leaves the list resets its episode")  // 180 at 0; [] at 30; 180 at 50; 180 at 100 → empty; 180 at 110 → one alert
@Test("Zero sustain alerts on the first qualifying sample")  // policy sustain 0; 180 at 0 → one alert
@Test("Sustain descriptions", arguments: [(30, "30 seconds"), (60, "1 minute"), (120, "2 minutes"), (300, "5 minutes")])
```

- [ ] **Step 2: Add both files to the pbxproj and run the suite to see it fail**

Expected: build fails, `CPUAlertTracker` undefined.

- [ ] **Step 3: Implement the tracker**

State: `episodeStarts: [String: Date]`, `lastNotified: [String: Date]`. `observe`:

1. Drop episode entries whose key is not in `candidates`.
2. For each candidate: if `percentOfCore < Double(policy.thresholdPercentOfCore)`, remove its episode and continue. Otherwise `start = episodeStarts[key] ?? now` (store it). If `now.timeIntervalSince(start) < Double(policy.sustainSeconds)`, continue. If `alertedThisEpisode` (tracked as `notifiedEpisodes: Set<String>`), continue. If `lastNotified[key]` is within `cooldownSeconds` of `now`, continue. Otherwise emit the alert, record `lastNotified[key] = now`, insert into `notifiedEpisodes`.
3. When an episode ends (drops below or leaves the list), remove the key from `notifiedEpisodes` too.

`CPUAlert.title`: `"\(name) at \(Int(percentOfCore.rounded()))% CPU"`. `body`: `"Above \(policy.thresholdPercentOfCore)% of a core for \(CPUAlertPolicy.describe(sustainSeconds: policy.sustainSeconds))."`

- [ ] **Step 4: Run the suite**

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add SystemHeadroom/Grouping/CPUAlertTracker.swift SystemHeadroomTests/CPUAlertTrackerTests.swift SystemHeadroom.xcodeproj/project.pbxproj
git commit -m "feat(alerts): add the sustained CPU alert tracker"
```

### Task 7: Alert delivery and store wiring (Part 3, store)

**Files:**
- Create: `SystemHeadroom/App/AlertDelivery.swift` (G…04)
- Modify: `SystemHeadroom/Sampling/MonitorTick.swift:12-22`
- Modify: `SystemHeadroom/Sampling/SamplerService.swift:93-103`
- Modify: `SystemHeadroom/App/MonitorStore.swift`
- Modify: `SystemHeadroom/App/SystemHeadroomApp.swift:5`
- Test: `SystemHeadroomTests/StoreAlertTests.swift` (E…17)
- Modify: `SystemHeadroomTests/MonitorStorePreferencesTests.swift`
- Modify: `SystemHeadroom.xcodeproj/project.pbxproj` (eight lines)

**Interfaces:**
- Consumes: `CPUAlertTracker`, `CPUAlertPolicy`, `CPUAlertCandidate`, `CPUAlert` from Task 6.
- Produces:

```swift
@MainActor protocol AlertDelivery: AnyObject {
  func requestAuthorization()
  func deliver(_ alert: CPUAlert)
}
@MainActor final class NotificationAlertDelivery: NSObject, AlertDelivery, UNUserNotificationCenterDelegate
@MainActor final class NoOpAlertDelivery: AlertDelivery   // used by MonitorStore.preview
```

`MonitorTick` gains `let logicalCoreCount: Int` (after `processMemoryMetric`; `SamplerService.tick` fills it; update the two fixture constructions in `SamplerBurstTests` and `PortGroupBuilderTests` if they build ticks; grep `MonitorTick(`).

`MonitorStore` gains: `var cpuAlertsEnabled: Bool`, `var cpuAlertThresholdPercent: Int`, `var cpuAlertSustainSeconds: Int` (defaults false, 90, 60; keys `cpuAlertsEnabled`, `cpuAlertThresholdPercent`, `cpuAlertSustainSeconds`), `var isSampling: Bool { timerTask != nil }`, `private(set) var logicalCoreCount = 1`, `private var needsBackgroundSampling: Bool { showsMenuBarText || cpuAlertsEnabled }`, `func evaluateAlerts(groups: [AppGroup], now: Date)`, `static func candidates(from groups: [AppGroup], convention: CPUConvention, logicalCoreCount: Int) -> [CPUAlertCandidate]`, and an `alertDelivery: AlertDelivery = NotificationAlertDelivery()` init parameter. `MonitorStore.preview` passes `NoOpAlertDelivery()`.

- [ ] **Step 1: Write the failing preference tests (append to `MonitorStorePreferencesTests`)**

Each test builds a `RecordingAlertDelivery` (a `@MainActor final class` in the test file: `var authorizationRequests = 0; var delivered: [CPUAlert] = []`) and passes it as `alertDelivery:`.

```swift
@Test("Alert preferences default to off, 90 percent, one minute")
// cpuAlertsEnabled == false, cpuAlertThresholdPercent == 90, cpuAlertSustainSeconds == 60, isSampling == false
@Test("Alert preferences round trip through a fresh store")
// set true, 75, 120; new store on same defaults reads the same three
@Test("Enabling alerts with the popover closed starts sampling and asks once")
// cpuAlertsEnabled = true → isSampling, delivery.authorizationRequests == 1
@Test("Disabling alerts with the popover closed and menu text off stops sampling")
// enable, then disable → isSampling == false
@Test("Disabling alerts with the popover open keeps sampling")
// popoverDidAppear; enable; disable → isSampling == true; popoverDidDisappear
```

- [ ] **Step 2: Write the failing store alert tests**

```swift
@Suite("Store alerts")
@MainActor
struct StoreAlertTests {
  // makeStore(): UUID defaults suite, SamplerService(logicalCoreCount: 14), .sandboxed, no-op terminator, RecordingAlertDelivery
  // group(_ key: String, cpu: Double) builds an AppGroup with one child

  @Test("Candidates convert machine-capacity percent to percent of one core")
  // candidates(from: [group("a", cpu: 10)], convention: .machineCapacity, logicalCoreCount: 14).first?.percentOfCore == 140
  // under .perCore stays 10; a group with cpuPercent nil yields no candidate

  @Test("A group over the threshold on a 14-core tick is delivered once")
  // alerts on, sustain 0, threshold 90; await store.refreshNow() (priming tick sets logicalCoreCount to 14, all cpu nil)
  // evaluateAlerts(groups: [group("chrome", cpu: 10), group("slack", cpu: 5)], now: Date()) → delivered.count == 1, groupKey "chrome", percentOfCore == 140

  @Test("Alerts off delivers nothing")
  // same setup with cpuAlertsEnabled false → delivered.isEmpty
}
```

- [ ] **Step 3: Add the files to the pbxproj and run both suites to see them fail**

Expected: build fails, `alertDelivery` unknown parameter.

- [ ] **Step 4: Implement `AlertDelivery.swift`**

`NotificationAlertDelivery.requestAuthorization()`: set `center.delegate = self`, then `Task { try? await center.requestAuthorization(options: [.alert, .sound]) }`. `deliver(_:)`: build `UNMutableNotificationContent` (title, body, `.default` sound), `UNNotificationRequest(identifier: "cpu-alert-\(alert.groupKey)", content:, trigger: nil)`, `center.add(request)`. Touch `UNUserNotificationCenter.current()` only inside these two methods. The delegate method is `nonisolated func userNotificationCenter(_:willPresent:withCompletionHandler:)` calling the handler with `[.banner, .sound]`.

- [ ] **Step 5: Implement the store changes**

- `cpuAlertsEnabled.didSet`: persist; if on, `alertDelivery.requestAuthorization()` then `start()`; if off, `alertTracker = CPUAlertTracker()` and `stopIfIdle()`.
- `cpuAlertThresholdPercent.didSet` and `cpuAlertSustainSeconds.didSet`: persist only.
- Init: read the three keys (`integer(forKey:)` of 0 means unset → default). Replace `if showsMenuBarText { start() }` with `if needsBackgroundSampling { start() }`.
- `showsMenuBarText.didSet` and `popoverDidDisappear`: replace the direct checks with `stopIfIdle()`, a private method: `guard !isPopoverOpen, !needsBackgroundSampling else { return }; stop()`.
- `refreshNow`: after `lastUpdated = Date()`, set `logicalCoreCount = tick.logicalCoreCount` and call `evaluateAlerts(groups: topCPUGroups, now: Date())`.
- `evaluateAlerts`: `guard cpuAlertsEnabled else { return }`; build the policy from the two preferences; `candidates(from:convention:logicalCoreCount:)`; `alertTracker.observe(...)`; `deliver` each.
- `candidates(from:)`: `compactMap` groups with non-nil `cpuPercent`; `percentOfCore = convention == .machineCapacity ? cpu * Double(logicalCoreCount) : cpu`.
- `SystemHeadroomApp`: `MonitorStore()` keeps the default, which is `NotificationAlertDelivery()`.

- [ ] **Step 6: Run both suites plus `StoreSamplingCadenceTests` and `StoreTerminationTests`**

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add SystemHeadroom/App/AlertDelivery.swift SystemHeadroom/App/MonitorStore.swift SystemHeadroom/Sampling/MonitorTick.swift SystemHeadroom/Sampling/SamplerService.swift SystemHeadroomTests/StoreAlertTests.swift SystemHeadroomTests/MonitorStorePreferencesTests.swift SystemHeadroom.xcodeproj/project.pbxproj
git commit -m "feat(alerts): deliver sustained CPU notifications from the store"
```

Add any fixture files that needed the new `MonitorTick` field to the same commit.

### Task 8: Alerts settings and Help (Part 3, UI)

**Files:**
- Modify: `SystemHeadroom/UI/SettingsView.swift:45-63`
- Modify: `SystemHeadroom/UI/HelpView.swift:76-87`

**Interfaces:**
- Consumes: the three store preferences and `CPUAlertPolicy.describe(sustainSeconds:)`.

- [ ] **Step 1: Add the "Alerts" section after "Monitoring"**

```swift
Section("Alerts") {
  Toggle("Notify me about sustained CPU use", isOn: $store.cpuAlertsEnabled)
  Picker("Above", selection: $store.cpuAlertThresholdPercent) {
    ForEach([50, 75, 90], id: \.self) { Text("\($0)%").tag($0) }
  }
  .disabled(!store.cpuAlertsEnabled)
  Picker("For at least", selection: $store.cpuAlertSustainSeconds) {
    ForEach([30, 60, 120, 300], id: \.self) { Text(CPUAlertPolicy.describe(sustainSeconds: $0)).tag($0) }
  }
  .disabled(!store.cpuAlertsEnabled)
  Text("Percent of one core, the way Activity Monitor counts. Alerts keep sampling running while the popover is closed, like the menu bar percent does.")
    .font(.caption)
    .foregroundStyle(.secondary)
}
```

- [ ] **Step 2: Add the Help "Alerts" section after "Keep it current"**

`HelpSection("Alerts", systemImage: "bell")` with two facts: "Sustained CPU alerts" ("Turn on alerts in General to get a notification when an app stays above your threshold for as long as you choose. macOS asks once for permission. If nothing arrives, check System Settings, then Notifications, then System Headroom.") and "What counts" ("Alerts measure against one core, the way Activity Monitor does, so a row shown as 7% of the whole Mac can still be a full core. You get one notification per episode, and the same app waits five minutes before it can alert again.").

- [ ] **Step 3: Run the visual suite and a Debug build**

Run: `-only-testing:SystemHeadroomTests/PopoverVisualTests`
Expected: pass; the Help PNGs regenerate.

- [ ] **Step 4: Commit**

```bash
git add SystemHeadroom/UI/SettingsView.swift SystemHeadroom/UI/HelpView.swift
git commit -m "feat(settings): add the Alerts section and Help"
```

### Task 9: Version bump to 1.5.0 (17)

**Files:**
- Modify: `Configuration/Shared.xcconfig`, `SystemHeadroomTests/AppIdentityTests.swift` (via script)

- [ ] **Step 1: Run the bump script**

```bash
python3 Scripts/bump-direct-version.py --version 1.5.0 --build 17
git diff --stat
```

Expected: two files changed; `MARKETING_VERSION = 1.5.0`, `CURRENT_PROJECT_VERSION = 17`, pins "1.5.0" and "17".

- [ ] **Step 2: Run `AppIdentityTests`**

Expected: pass.

- [ ] **Step 3: Commit**

```bash
git add Configuration/Shared.xcconfig SystemHeadroomTests/AppIdentityTests.swift
git commit -m "build(release): bump the shared version to 1.5.0 (17)"
```

### Task 10: Full verification

- [ ] **Step 1: Full suite**

Run the whole test action, log to the scratchpad.
Expected: every suite passes except the four pre-existing `PortsSamplerLiveTests` failures. Record the counts.

- [ ] **Step 2: Direct build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Scripts/build-direct.sh
```

Expected: success, no signing warnings.

- [ ] **Step 3: Dash and voice sweep on shipped prose**

```bash
git diff 17b3f7f -- '*.swift' '*.md' | grep -nE '—|–| -- '
```

Expected: no matches in prose (code tokens excluded by eye).

- [ ] **Step 4: Close out**

Update the dashboard (dashboard-builder), `tasks/todo.md` "Resuming From Here", distill or delete `tasks/implementation-notes.md`, remove scratch files, then deliver the change report and quiz. Do not push or open a PR without Vinny's go-ahead.
