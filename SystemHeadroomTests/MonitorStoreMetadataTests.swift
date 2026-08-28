import Testing

@testable import SystemHeadroom

@Suite("Monitor store metadata table")
struct MonitorStoreMetadataTests {
  /// NSRunningApplication reports a process identifier of -1 once the app has
  /// terminated, so a sweep that catches two apps mid-exit hands the table two
  /// entries under the same key. Building the table with
  /// Dictionary(uniqueKeysWithValues:) traps on that — a crash of the whole
  /// app, observed as "Fatal error: Duplicate values for key: '-1'".
  @Test("Two terminated applications in one sweep do not trap")
  @MainActor
  func terminatedApplicationsDoNotTrap() {
    let entries = [
      AppMetadata(pid: 412, bundleIdentifier: "com.apple.Safari", name: "Safari"),
      AppMetadata(pid: -1, bundleIdentifier: nil, name: "Unknown"),
      AppMetadata(pid: -1, bundleIdentifier: nil, name: "Unknown"),
    ]

    let table = MonitorStore.metadataTable(from: entries)

    #expect(table[412]?.name == "Safari")
    #expect(table[-1] == nil)
    #expect(table.count == 1)
  }

  /// No process the sampler can report has a non-positive pid, so a terminated
  /// entry could never match a row anyway.
  @Test("Live applications are keyed by pid")
  @MainActor
  func liveApplicationsAreKeyedByPid() {
    let entries = [
      AppMetadata(pid: 1, bundleIdentifier: "com.apple.launchd", name: "launchd"),
      AppMetadata(pid: 900, bundleIdentifier: "com.apple.Terminal", name: "Terminal"),
    ]

    let table = MonitorStore.metadataTable(from: entries)

    #expect(table.count == 2)
    #expect(table[900]?.bundleIdentifier == "com.apple.Terminal")
  }
}
