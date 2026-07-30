import Testing

@testable import MacHeadroom

@Suite("Grouping engine")
struct GroupingEngineTests {
  @Test("Helper processes consolidate under their parent app via the pid chain")
  func helperConsolidation() {
    let measurements = [
      measurement(pid: 100, parentPID: 1, name: "Google Chrome", cpuPercent: 5, residentBytes: 100),
      measurement(
        pid: 101, parentPID: 100, name: "Google Chrome Helper (Renderer)", cpuPercent: 3,
        residentBytes: 50),
      measurement(
        pid: 102, parentPID: 100, name: "Google Chrome Helper (GPU)", cpuPercent: 2,
        residentBytes: 30),
    ]
    let metadata: [Int32: AppMetadata] = [
      100: AppMetadata(pid: 100, bundleIdentifier: "com.google.Chrome", name: "Google Chrome")
    ]

    let groups = GroupingEngine.group(measurements: measurements, metadataByPID: metadata)

    #expect(groups.count == 1)
    let chrome = try! #require(groups.first)
    #expect(chrome.groupKey == "com.google.Chrome")
    #expect(chrome.processCount == 3)
    #expect(chrome.cpuPercent == 10)
    #expect(chrome.memoryBytes == 180)
  }

  @Test("A helper reparented away from its app still groups by name")
  func nameHeuristicFallback() {
    let measurements = [
      measurement(pid: 400, parentPID: 1, name: "Safari Helper (Renderer)", cpuPercent: 1, residentBytes: 40),
    ]
    let metadata: [Int32: AppMetadata] = [
      401: AppMetadata(pid: 401, bundleIdentifier: "com.apple.Safari", name: "Safari")
    ]

    let groups = GroupingEngine.group(measurements: measurements, metadataByPID: metadata)

    #expect(groups.count == 1)
    let safari = try! #require(groups.first)
    #expect(safari.groupKey == "com.apple.Safari")
    #expect(safari.name == "Safari")
    #expect(safari.processCount == 1)
  }

  @Test("A helper with no ancestor and no name match stands alone")
  func orphanedHelperStandsAlone() {
    let measurements = [
      measurement(pid: 200, parentPID: 1, name: "Orphaned Helper", cpuPercent: 0, residentBytes: 10),
    ]

    let groups = GroupingEngine.group(measurements: measurements, metadataByPID: [:])

    #expect(groups.count == 1)
    let orphan = try! #require(groups.first)
    #expect(orphan.groupKey == "name:Orphaned")
    #expect(orphan.name == "Orphaned")
    #expect(orphan.bundleIdentifier == nil)
  }

  @Test("A process with no Helper suffix and no metadata falls back to its own pid")
  func unmatchedStragglerFallsBackToPID() {
    let measurements = [
      measurement(pid: 300, parentPID: 1, name: "com.example.somedaemon", cpuPercent: 0, residentBytes: 5),
    ]

    let groups = GroupingEngine.group(measurements: measurements, metadataByPID: [:])

    #expect(groups.count == 1)
    #expect(groups.first?.groupKey == "pid:300")
  }

  @Test("Groups with an equal metric value break ties by name")
  func tieBreakingByName() {
    let groups = [
      appGroup(key: "com.example.Zebra", name: "Zebra", cpuPercent: 5),
      appGroup(key: "com.example.Apple", name: "Apple", cpuPercent: 5),
    ]

    let top = GroupingEngine.topGroups(from: groups, by: \.cpuPercent, limit: 10)

    #expect(top.map(\.name) == ["Apple", "Zebra"])
  }

  @Test("Top-N selection respects the limit even with more groups available")
  func topGroupsRespectsLimit() {
    let groups = (0..<20).map { index in
      appGroup(key: "pid:\(index)", name: "App\(index)", cpuPercent: Double(index))
    }

    let top = GroupingEngine.topGroups(from: groups, by: \.cpuPercent, limit: 10)

    #expect(top.count == 10)
    #expect(top.first?.name == "App19")
  }

  @Test("Groups without a metric reading are excluded from the top list")
  func topGroupsExcludesNilMetrics() {
    let groups = [
      appGroup(key: "com.example.Idle", name: "Idle", cpuPercent: 0),
      appGroup(key: "com.example.Unknown", name: "Unknown", cpuPercent: nil),
      appGroup(key: "com.example.Busy", name: "Busy", cpuPercent: 12),
    ]

    let top = GroupingEngine.topGroups(from: groups, by: \.cpuPercent, limit: 10)

    #expect(top.map(\.name) == ["Busy", "Idle"])
  }

  @Test("A priming tick with no CPU readings yields an empty top list, not an alphabetical one")
  func primingTickYieldsEmptyTopList() {
    let groups = (0..<12).map { index in
      appGroup(key: "pid:\(index)", name: "App\(index)", cpuPercent: nil)
    }

    let top = GroupingEngine.topGroups(from: groups, by: \.cpuPercent, limit: 10)

    #expect(top.isEmpty)
  }
}

private func measurement(
  pid: Int32,
  parentPID: Int32,
  name: String,
  cpuPercent: Double?,
  residentBytes: UInt64
) -> ProcessMeasurement {
  ProcessMeasurement(
    snapshot: ProcessSnapshot(
      pid: pid,
      parentPID: parentPID,
      userID: 501,
      name: name,
      startIdentity: "\(pid):0",
      cpuTimeTicks: 0,
      residentBytes: residentBytes
    ),
    cpuPercent: cpuPercent
  )
}

private func appGroup(key: String, name: String, cpuPercent: Double?) -> AppGroup {
  AppGroup(
    groupKey: key,
    name: name,
    bundleIdentifier: key,
    representativePID: 1,
    cpuPercent: cpuPercent,
    memoryBytes: 0,
    children: []
  )
}
