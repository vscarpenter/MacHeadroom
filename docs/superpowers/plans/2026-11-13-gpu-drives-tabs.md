# GPU and Drives tabs implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GPU and Drives tabs to the System Headroom popover in both appearances, with SSD health and temperature in the Direct edition only.

**Architecture:** Two samplers read IORegistry properties and Foundation volume values. Pure parsers, deltas, classifiers, and builders sit between the samplers and the views, so fixtures cover the logic. `SamplerService` owns the previous counters and the clock. `MonitorStore` republishes. Each appearance renders the same `StatRow` values.

**Tech Stack:** Swift 6 (language mode 6.0, strict concurrency complete, warnings as errors), SwiftUI, IOKit, Swift Testing, hosted test bundle inside the sandboxed app. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-13-gpu-drives-tabs-design.md`

## Global constraints

- Popover intrinsic size must not depend on content or capability. Porcelain header is a fixed 222 points, list a fixed 468. `PopoverLayoutTests` pins equal size for every new tab and state.
- No drive health UI in the App Store build. Health rows come only from `DriveHealthCapability.available`, decided from the app's own sandbox entitlement.
- The sandboxed app never calls the SMART bridge.
- Zero dependencies, no network, no new entitlement, no private framework.
- A missing registry key maps to nil or an unavailable state. Nothing traps on an unexpected type.
- The actor owns the clock. No caller passes a timestamp into `tick`.
- New source files need four `project.pbxproj` edits each. IDs are 24 hex characters. Next free: Sampling `D1…/D2…` `0D`, Grouping `F1…/F2…` `07`, UI `H1…/H2…` `12`, tests `E1…/E2…` `19`. Headers get a file reference and a group entry only.
- Shipped prose follows vinny-voice.
- Commits: Conventional Commits with scope, Claude-Session trailer, one commit per task. Never `git add -A`. `input/` stays untracked.
- Test command: `xcodebuild test -project SystemHeadroom.xcodeproj -scheme SystemHeadroom -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:SystemHeadroomTests/<Suite>`. Four `PortsSamplerLiveTests` fail on this Mac regardless (baseline: 151 tests, 147 pass).
- Rendered PNGs are readable only from an unsandboxed host: add `-derivedDataPath build/unsandboxed-tests ENABLE_APP_SANDBOX=NO CODE_SIGN_ENTITLEMENTS=SystemHeadroom/SystemHeadroomDirect.entitlements -only-testing:SystemHeadroomTests/PopoverVisualTests`.

## Review focus

1. A GPU client whose creator string has no comma, or a pid that does not fit `Int32`: skipped, not trapped. Pinned in Task 1 (`parseCreator`).
2. A process that closes a GPU client between ticks, so its summed counter drops: no percent that tick, never a negative or wrapped value. Pinned in Task 1 (`GPUDelta`).
3. A volume whose free space exceeds its total (a filesystem race): used clamps at zero, the bar stays in 0 to 1. Pinned in Task 3 (`usedFraction`).
4. An external disk ejected between ticks, then a different disk mounted under the same BSD name: counters drop, so no throughput that tick. Pinned in Task 3 (`DiskActivityDelta`).
5. SMART reports 0 K, or wear above 100%: temperature shows as unknown, the wear bar clamps, the text keeps the real number. Pinned in Task 4 and Task 6.

---

### Task 0: Evidence, spec, and plan

**Files:** `Evidence/gpu-drives-spike/*`, `SANDBOX_NOTES.md`, this plan, the spec.

- [ ] Commit the spike evidence and the sandbox addendum (`docs(sandbox): …`).
- [ ] Commit the spec and plan (`docs(spec): …`).

### Task 1: GPU reading, parser, and delta (pure)

**Files:** Create `SystemHeadroom/Sampling/GPUStatsParser.swift`, `SystemHeadroomTests/GPUStatsParserTests.swift`.

**Produces:**

```swift
struct GPUReading: Sendable, Equatable {
  var model: String?
  var coreCount: Int?
  var deviceUtilizationPercent: Double
  var rendererUtilizationPercent: Double?
  var tilerUtilizationPercent: Double?
  var allocatedMemoryBytes: UInt64?
  var inUseMemoryBytes: UInt64?
  var gpuTimeNanosecondsByPID: [Int32: UInt64]
  var clientNamesByPID: [Int32: String]
}
enum GPUStatsParser {
  static func reading(accelerator: [String: Any], clients: [[String: Any]]) -> GPUReading?
  static func parseCreator(_ creator: String) -> (pid: Int32, name: String)?
}
enum GPUDelta {
  static func percents(
    previous: [Int32: UInt64], current: [Int32: UInt64],
    wallTimeNanoseconds: UInt64, identityChanged: (Int32) -> Bool
  ) -> [Int32: Double]
}
```

- [ ] Tests first: a full reading (27, 27, 12, both memory counters, model, cores); no `Device Utilization %` returns nil; `model` as `Data` with a trailing NUL; two clients for one pid sum; a client with an empty `AppUsage` contributes 0; `parseCreator("pid 653, WindowServer")` is `(653, "WindowServer")`; `"pid x, y"`, `"653"`, and `"pid 99999999999, z"` are nil; a name containing a comma keeps the comma.
- [ ] Delta tests: 187,564,500 ns over 13,649,697,292 ns is 1.374% within 0.001; no previous entry yields no key; a backward counter yields no key; zero wall time yields an empty result; `identityChanged` true yields no key.
- [ ] Implement, run `GPUStatsParserTests`, commit.

### Task 2: GPU sampler and app ranking

**Files:** Create `Sampling/IORegistry.swift`, `Sampling/GPUSampler.swift`, `Grouping/GPUAppUsage.swift`, `SystemHeadroomTests/GPUSamplerLiveTests.swift`, `SystemHeadroomTests/GPUUsageBuilderTests.swift`.

**Produces:**

```swift
enum IORegistry {
  static func forEachService(className: String, _ body: (io_service_t) -> Void)
  static func forEachService(matching: [String: Any], _ body: (io_service_t) -> Void)
  static func forEachChild(of entry: io_registry_entry_t, _ body: (io_registry_entry_t) -> Void)
  static func property(_ key: String, of entry: io_registry_entry_t) -> Any?
  static func searchParents(_ key: String, from entry: io_registry_entry_t) -> Any?
  static func searchChildren(_ key: String, from entry: io_registry_entry_t) -> Any?
}
enum GPUSampler { static func sample() -> GPUReading? }

struct GPUAppUsage: Sendable, Equatable, Identifiable {
  let groupKey: String; let name: String; let bundleIdentifier: String?
  let representativePID: Int32; let gpuPercent: Double; let processCount: Int
  let appGroup: AppGroup?          // nil marks a system row
  var id: String { "gpu:\(groupKey)" }
  var isSystem: Bool { appGroup == nil }
}
enum GPUUsageBuilder {
  static let floorPercent = 0.05
  static func build(
    percentByPID: [Int32: Double], groups: [AppGroup],
    fallbackNamesByPID: [Int32: String], limit: Int
  ) -> [GPUAppUsage]
}
```

- [ ] Builder tests: two pids of one group sum into one row; a pid in no group becomes a system row keyed `gpu-pid:<pid>` named from the fallback, or `pid <pid>` without one; 0.04 is dropped and 0.05 kept; equal percents order by name then key; 12 rows in, 10 out.
- [ ] Live tests (sandboxed host): `GPUSampler.sample()` is non-nil with utilization in 0 to 100; at least one client pid; the sweep finishes in under 250 ms and prints its duration.
- [ ] Implement, run both suites, commit.

### Task 3: Volumes and disk activity

**Files:** Create `Sampling/VolumeSampler.swift`, `Sampling/DiskActivity.swift`, `SystemHeadroomTests/VolumeClassifierTests.swift`, `SystemHeadroomTests/DiskActivityTests.swift`, `SystemHeadroomTests/DriveSamplerLiveTests.swift`.

**Produces:**

```swift
struct DiskCounters: Sendable, Equatable { let readBytes: UInt64; let writeBytes: UInt64 }
struct DiskActivity: Sendable, Equatable { let readBytesPerSecond: Double; let writeBytesPerSecond: Double }
enum DiskActivityDelta {
  static func activity(previous: DiskCounters?, current: DiskCounters, wallTimeNanoseconds: UInt64) -> DiskActivity?
}
enum DriveLocation: Sendable, Equatable { case `internal`, external, unknown }
enum DriveMedium: Sendable, Equatable { case solidState, rotational }
struct VolumeFacts: Sendable, Equatable {  // everything optional or defaulted but mountPath and name
  var mountPath: String; var name: String
  var totalBytes: UInt64; var availableBytes: UInt64; var importantAvailableBytes: UInt64
  var isLocal: Bool; var isStartup: Bool; var formatDescription: String?
  var physicalDisk: String?; var interconnect: String?; var interconnectLocation: String?
  var mediumType: String?; var counters: DiskCounters?
}
struct VolumeSnapshot: Sendable, Equatable, Identifiable {
  let mountPath: String; let name: String; let totalBytes: UInt64; let freeBytes: UInt64
  let isStartup: Bool; let location: DriveLocation; let medium: DriveMedium?
  let interconnect: String?; let formatDescription: String?; let physicalDisk: String?
  var id: String { "volume:\(mountPath)" }
  var usedBytes: UInt64 { get }
  var usedFraction: Double { get }   // clamped to 0...1, 0 when total is 0
}
enum VolumeClassifier {
  static func snapshots(from facts: [VolumeFacts]) -> [VolumeSnapshot]
  static func counters(from facts: [VolumeFacts]) -> [String: DiskCounters]
}
enum VolumeSampler { static func sampleFacts() -> [VolumeFacts] }
```

- [ ] Classifier tests, with the measured shapes as fixtures: internal APFS startup volume kept, free space 179,612,178,956 from important usage; external USB rotational volume kept, free space from plain available because important usage is 0; `Virtual Interface` disk image dropped; non-local NFS mount dropped; a startup volume with no physical disk kept; zero-total volume dropped; order is startup first, then `localizedStandardCompare` on name; `usedFraction` clamps when free exceeds total.
- [ ] Activity tests: no previous is nil; 51,314,688 bytes over 1 s is 51,314,688 bytes per second; half a second doubles the rate; a backward counter is nil; zero wall time is nil.
- [ ] Live tests (sandboxed host): facts contain a startup volume with total above 0, a physical disk, and counters; `snapshots` keeps it; a tick carries volumes.
- [ ] Implement, run the three suites, commit.

### Task 4: Drive health (Direct only)

**Files:** Create `Sampling/NVMeSMARTBridge.h`, `Sampling/BridgingHeader.h`, `Sampling/DriveHealthSampler.swift`, `SystemHeadroomTests/DriveHealthTests.swift`. Modify `Configuration/Shared.xcconfig` and both test configurations in the project file (`SWIFT_OBJC_BRIDGING_HEADER` to `BridgingHeader.h`).

**Produces:**

```c
typedef struct { uint8_t criticalWarning; uint16_t temperatureKelvin;
  uint8_t availableSpare; uint8_t availableSpareThreshold; uint8_t percentageUsed; } HeadroomNVMeHealth;
static inline kern_return_t HeadroomReadNVMeHealth(io_service_t service, HeadroomNVMeHealth *health);
```

```swift
enum DriveHealthCapability: Sendable, Equatable {
  case available, sandboxed
  static let current: DriveHealthCapability
}
struct DriveHealth: Sendable, Equatable, Identifiable {
  let physicalDisk: String?; let criticalWarning: UInt8; let percentageUsed: Int
  let availableSparePercent: Int; let availableSpareThresholdPercent: Int
  let temperatureCelsius: Int?
  var hasWarning: Bool { get }
  init(criticalWarning: UInt8, temperatureKelvin: UInt16, availableSpare: UInt8,
       availableSpareThreshold: UInt8, percentageUsed: UInt8, physicalDisk: String?)
}
enum DriveHealthSampler { static func sample() -> [DriveHealth] }
```

- [ ] Tests: 311 K is 38 C; 0 K is nil; warning byte 0 with spare 100 over threshold 99 has no warning; warning byte 1 has one; spare 5 under threshold 10 has one; the capability is `.sandboxed` in the sandboxed host and `.available` in an unsandboxed one; in an unsandboxed host only (`.enabled(if:)`), the live read returns at least one device with wear in 0 to 255.
- [ ] Implement, run `DriveHealthTests` sandboxed and unsandboxed, run `PortTableABITests` to prove the bridging header move, commit.

### Task 5: Tick, sampler service, and store

**Files:** Modify `Sampling/MonitorTick.swift`, `Sampling/SamplerService.swift`, `App/MonitorStore.swift`, `UI/PreviewFixtures.swift`. Extend `GPUSamplerLiveTests`, `DriveSamplerLiveTests`. Create `SystemHeadroomTests/HardwareTickTests.swift`.

**Produces:**

```swift
struct GPUSample: Sendable, Equatable {
  let model: String?; let coreCount: Int?; let utilizationPercent: Double
  let rendererPercent: Double?; let tilerPercent: Double?
  let allocatedMemoryBytes: UInt64?; let inUseMemoryBytes: UInt64?
  let processPercents: [Int32: Double]?   // nil until a second tick
  let processNames: [Int32: String]
}
// MonitorTick gains, all with defaults:
var gpu: GPUSample? = nil
var volumes: [VolumeSnapshot] = []
var diskActivity: [String: DiskActivity] = [:]
var driveHealth: [DriveHealth] = []
// SamplerService.init gains:
driveHealthReader: (@Sendable () -> [DriveHealth])? = <live reader when capability is available, else nil>,
driveHealthIntervalNanoseconds: UInt64 = 60_000_000_000
// MonitorStore gains:
private(set) var gpu: GPUSample?
private(set) var topGPUApps: [GPUAppUsage]?   // nil until a second tick
private(set) var volumes: [VolumeSnapshot]
private(set) var diskActivity: [String: DiskActivity]
private(set) var driveHealth: [DriveHealth]
```

- [ ] Tests: a counting reader with the default interval is called once across two ticks; with interval 0 it is called twice; a nil reader leaves `driveHealth` empty; the first tick has `gpu?.processPercents == nil` and the second has a dictionary; the second tick has disk activity for the startup disk; after `refreshNow` twice the store publishes `gpu`, `topGPUApps`, and `volumes`.
- [ ] Implement, run the suites plus `SamplerBurstTests`, commit.

### Task 6: Presentation (pure)

**Files:** Create `UI/StatRow.swift`, `SystemHeadroomTests/HardwarePresentationTests.swift`. Modify `UI/ValueFormatting.swift`.

**Produces:**

```swift
struct StatRow: Equatable, Identifiable {
  let id: String; let symbol: String; let title: String; let subtitle: String
  let value: String; let usedFraction: Double?; let isAccented: Bool
  var accessibilityLabel: String { get }
}
enum GPUPresentation {
  static func headroomPercent(_ gpu: GPUSample?) -> Int?
  static func usageDetail(_ gpu: GPUSample?) -> String
  static func statRows(_ gpu: GPUSample, installedMemoryBytes: UInt64) -> [StatRow]
}
enum DrivesPresentation {
  static func headroomPercent(_ volumes: [VolumeSnapshot]) -> Int?
  static func usageDetail(_ volumes: [VolumeSnapshot]) -> String
  static func kindLine(_ volume: VolumeSnapshot) -> String
  static func rows(volumes: [VolumeSnapshot], activity: [String: DiskActivity],
                   health: [DriveHealth], locale: Locale) -> [StatRow]
}
// ValueFormatting gains:
static func diskBytes(_ value: UInt64) -> String          // ByteCountFormatter, .file
static func megabytesPerSecond(_ bytesPerSecond: Double) -> String   // "0.2", "51", decimal megabytes
static func throughput(_ activity: DiskActivity?) -> String          // "R 0.2 · W 51 MB/s", dashes for nil
static func temperature(celsius: Int, locale: Locale) -> String
```

Exact copy: titles "GPU Utilization", "GPU Memory", "Disk Activity", "SSD Health", "Drive Temperature". Health value "Healthy" or "Check drive". Health subtitle "No warnings · N% wear" or "Warning reported · N% wear". Kind line parts joined by " · ": "Internal SSD", "Internal HDD", "External SSD", "External HDD", "Internal", "External", or "Drive"; then the capacity; then the format when internal or the interconnect when external and known. Unavailable detail lines: "GPU statistics unavailable", "Drives unavailable".

- [ ] Tests cover every string above, the 27/12 subtitle, allocated over installed as the memory bar, the startup row accent, the wear bar clamp at 1.0 for 130% wear with "130% wear" in the text, a nil temperature omitting the row, `en_US` showing °F and `en_GB` showing °C, throughput at 0, 0.2, 9.96, 51, and nil.
- [ ] Implement, run the suite, commit.

### Task 7: Five tabs and the Classic panes

**Files:** Modify `UI/PopoverTab.swift`, `UI/PopoverView.swift`. Create `UI/HardwarePaneViews.swift`. Extend `PopoverLayoutTests`.

- [ ] Layout tests first: Classic GPU and Drives panes equal the CPU pane's height when populated, empty, and unavailable; health rows present and absent change nothing; capability on and off changes nothing on the GPU tab.
- [ ] Implement `StatRowView`, `GPUAppRowView`, `GPUPaneView`, `DrivesPaneView`; branch the list on the tab; run `PopoverLayoutTests`, commit.

### Task 8: Porcelain header and panes

**Files:** Modify `UI/MaxHeadroomPopoverView.swift`. Extend `PopoverLayoutTests`, `PopoverVisualTests`.

- [ ] Layout tests first: the Porcelain equivalents of Task 7, plus header height independent of tab.
- [ ] Move the tab bar to a full-width row, header height 222. Add `PorcelainStatRowView` and `PorcelainGPUAppRowView`. Add GPU and Drives fixtures to the visual test's list.
- [ ] Render unsandboxed, read the PNGs for both tabs in light and dark and for Classic, fix what the look shows, commit.

### Task 9: Help, docs, and the full pass

**Files:** Modify `UI/HelpView.swift`, `README.md`, `CLAUDE.md`, `tasks/todo.md`, `tasks/lessons.md`.

- [ ] Help copy per the spec. README feature and architecture lines. CLAUDE.md gains the registry-only and health-gating constraint.
- [ ] Full suite: the only failures are the four known live-port cases.
- [ ] `Scripts/build-direct.sh`, launch the Direct build, confirm in the unified log that the health read ran. Launch the sandboxed Debug build, confirm no SMART denial is logged.
- [ ] Update `tasks/todo.md` with Resuming From Here, commit.
