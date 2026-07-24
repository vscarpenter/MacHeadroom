#if DEBUG
  import Foundation

  enum PreviewFixtures {
    @MainActor
    static func makeStore() -> MonitorStore {
      var chromeChildren: [ProcessMeasurement] = []
      for index in 1...14 {
        let name = index == 1 ? "Google Chrome" : "Google Chrome Helper (Renderer)"
        let pid = Int32(1000 + index)
        let residentBytes = UInt64(120_000_000 - index * 4_000_000)
        let snapshot = ProcessSnapshot(
          pid: pid,
          parentPID: 1000,
          userID: 501,
          name: name,
          startIdentity: "\(pid):0",
          cpuTimeTicks: 0,
          residentBytes: residentBytes
        )
        chromeChildren.append(
          ProcessMeasurement(snapshot: snapshot, cpuPercent: Double(18 - index)))
      }
      let chrome = AppGroup(
        groupKey: "com.google.Chrome",
        name: "Google Chrome",
        bundleIdentifier: "com.google.Chrome",
        representativePID: 1000,
        cpuPercent: 18.4,
        memoryBytes: chromeChildren.reduce(0) { $0 + $1.snapshot.residentBytes },
        children: chromeChildren
      )
      let xcode = AppGroup(
        groupKey: "com.apple.dt.Xcode",
        name: "Xcode",
        bundleIdentifier: "com.apple.dt.Xcode",
        representativePID: 2000,
        cpuPercent: 12.1,
        memoryBytes: 2_400_000_000,
        children: [
          ProcessMeasurement(
            snapshot: ProcessSnapshot(
              pid: 2000, parentPID: 1, userID: 501, name: "Xcode", startIdentity: "2000:0",
              cpuTimeTicks: 0, residentBytes: 2_400_000_000),
            cpuPercent: 12.1)
        ]
      )
      let slack = AppGroup(
        groupKey: "com.tinyspeck.slackmacgap",
        name: "Slack",
        bundleIdentifier: "com.tinyspeck.slackmacgap",
        representativePID: 3000,
        cpuPercent: 4.8,
        memoryBytes: 610_000_000,
        children: [
          ProcessMeasurement(
            snapshot: ProcessSnapshot(
              pid: 3000, parentPID: 1, userID: 501, name: "Slack", startIdentity: "3000:0",
              cpuTimeTicks: 0, residentBytes: 610_000_000),
            cpuPercent: 4.8)
        ]
      )
      let finder = AppGroup(
        groupKey: "com.apple.finder",
        name: "Finder",
        bundleIdentifier: "com.apple.finder",
        representativePID: 4000,
        cpuPercent: 0.3,
        memoryBytes: 240_000_000,
        children: [
          ProcessMeasurement(
            snapshot: ProcessSnapshot(
              pid: 4000, parentPID: 1, userID: 501, name: "Finder", startIdentity: "4000:0",
              cpuTimeTicks: 0, residentBytes: 240_000_000),
            cpuPercent: 0.3)
        ]
      )

      let cpuGroups = GroupingEngine.topGroups(
        from: [chrome, xcode, slack, finder], by: \.cpuPercent, limit: 10)
      let memoryGroups = GroupingEngine.topGroups(
        from: [chrome, xcode, slack, finder], by: { Double($0.memoryBytes) }, limit: 10)

      return MonitorStore.preview(
        cpuGroups: cpuGroups,
        memoryGroups: memoryGroups,
        summary: SystemSummary(
          cpuPercent: 34.2, memoryUsedBytes: 12_800_000_000, memoryTotalBytes: 36_000_000_000)
      )
    }
  }
#endif
