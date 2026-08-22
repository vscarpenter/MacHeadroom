#if DEBUG
  import Foundation

  enum PreviewFixtures {
    @MainActor
    static func makeStore(
      usesPorcelainAppearance: Bool = true, canTerminate: Bool = false
    ) -> MonitorStore {
      var chromeChildren: [ProcessMeasurement] = []
      for index in 1...14 {
        let name = index == 1 ? "Google Chrome" : "Google Chrome Helper (Renderer)"
        let pid = Int32(1000 + index)
        let memoryBytes = UInt64(120_000_000 - index * 4_000_000)
        let snapshot = ProcessSnapshot(
          pid: pid,
          parentPID: 1000,
          userID: 501,
          name: name,
          startIdentity: "\(pid):0",
          cpuTimeTicks: 0,
          memoryBytes: memoryBytes
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
        memoryBytes: chromeChildren.reduce(0) { $0 + $1.snapshot.memoryBytes },
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
              cpuTimeTicks: 0, memoryBytes: 2_400_000_000),
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
              cpuTimeTicks: 0, memoryBytes: 610_000_000),
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
              cpuTimeTicks: 0, memoryBytes: 240_000_000),
            cpuPercent: 0.3)
        ]
      )

      let spotlight = AppGroup(
        groupKey: "name:corespotlightd",
        name: "corespotlightd",
        bundleIdentifier: nil,
        representativePID: 5000,
        cpuPercent: 2.2,
        memoryBytes: 180_000_000,
        children: [
          ProcessMeasurement(
            snapshot: ProcessSnapshot(
              pid: 5000, parentPID: 1, userID: 501, name: "corespotlightd",
              startIdentity: "5000:0", cpuTimeTicks: 0, memoryBytes: 180_000_000),
            cpuPercent: 2.2)
        ]
      )

      let cpuGroups = GroupingEngine.topGroups(
        from: [chrome, xcode, slack, finder, spotlight], by: \.cpuPercent, limit: 10)
      let memoryGroups = GroupingEngine.topGroups(
        from: [chrome, xcode, slack, finder, spotlight], by: { Double($0.memoryBytes) }, limit: 10)

      return MonitorStore.preview(
        cpuGroups: cpuGroups,
        memoryGroups: memoryGroups,
        summary: SystemSummary(
          cpuPercent: 34.2, memoryUsedBytes: 12_800_000_000, memoryTotalBytes: 36_000_000_000),
        usesPorcelainAppearance: usesPorcelainAppearance,
        canTerminate: canTerminate,
        portGroups: makePortGroups(from: cpuGroups)
      )
    }

    /// Port fixtures shaped to exercise every row variant: app rows
    /// with tcp+udp badges, one row crowded enough for the +N overflow
    /// chip, and one system row.
    @MainActor
    static func makePortGroups(from groups: [AppGroup]) -> [PortGroup] {
      var rows = groups.prefix(2).enumerated().map { index, group in
        PortGroup(
          groupKey: group.groupKey, name: group.name,
          bundleIdentifier: group.bundleIdentifier,
          representativePID: group.representativePID,
          ports: [
            ListeningPort(number: UInt16(3000 + index), transport: .tcp),
            ListeningPort(number: UInt16(5300 + index), transport: .udp),
          ],
          appGroup: group)
      }
      if let overflowGroup = groups.dropFirst(2).first {
        rows.append(
          PortGroup(
            groupKey: "preview-overflow", name: overflowGroup.name,
            bundleIdentifier: overflowGroup.bundleIdentifier,
            representativePID: overflowGroup.representativePID,
            ports: (1...7).map { ListeningPort(number: UInt16(9000 + $0), transport: .tcp) },
            appGroup: overflowGroup))
      }
      rows.append(
        PortGroup(
          groupKey: "port-pid:1", name: "launchd", bundleIdentifier: nil,
          representativePID: 1, ports: [ListeningPort(number: 445, transport: .tcp)],
          appGroup: nil))
      return rows
    }
  }
#endif
