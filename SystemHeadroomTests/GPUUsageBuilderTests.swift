import Testing

@testable import SystemHeadroom

@Suite("GPU usage builder")
struct GPUUsageBuilderTests {
  private static func group(_ key: String, name: String, pids: [Int32]) -> AppGroup {
    let children = pids.map { pid in
      ProcessMeasurement(
        snapshot: ProcessSnapshot(
          pid: pid, parentPID: 1, userID: 501, name: name, startIdentity: "\(pid):0",
          cpuTimeTicks: 0, memoryBytes: 0),
        cpuPercent: 0)
    }
    return AppGroup(
      groupKey: key, name: name, bundleIdentifier: key, representativePID: pids[0],
      cpuPercent: 0, memoryBytes: 0, children: children)
  }

  @Test("Every process of one app folds into one row")
  func foldsOntoGroup() throws {
    let chrome = Self.group("com.google.Chrome", name: "Google Chrome", pids: [10, 11, 12])
    let rows = GPUUsageBuilder.build(
      percentByPID: [10: 3.0, 11: 4.5], groups: [chrome], fallbackNamesByPID: [:], limit: 10)

    let row = try #require(rows.first)
    #expect(rows.count == 1)
    #expect(row.gpuPercent == 7.5)
    #expect(row.name == "Google Chrome")
    #expect(row.bundleIdentifier == "com.google.Chrome")
    #expect(row.representativePID == 10)
    #expect(row.processCount == 3)
    #expect(row.appGroup == chrome)
    #expect(!row.isSystem)
    #expect(row.id == "gpu:com.google.Chrome")
  }

  @Test("A pid outside every group becomes a system row named from the registry")
  func systemRow() throws {
    let rows = GPUUsageBuilder.build(
      percentByPID: [653: 1.4, 700: 2.0], groups: [],
      fallbackNamesByPID: [653: "WindowServer", 700: ""], limit: 10)

    let windowServer = try #require(rows.first { $0.representativePID == 653 })
    #expect(windowServer.groupKey == "gpu-pid:653")
    #expect(windowServer.name == "WindowServer")
    #expect(windowServer.isSystem)
    #expect(windowServer.appGroup == nil)
    #expect(windowServer.processCount == 1)

    let unnamed = try #require(rows.first { $0.representativePID == 700 })
    #expect(unnamed.name == "pid 700")
  }

  @Test("Rows under the display floor are dropped")
  func floor() {
    let rows = GPUUsageBuilder.build(
      percentByPID: [1: 0.04, 2: 0.05], groups: [],
      fallbackNamesByPID: [1: "idle", 2: "barely"], limit: 10)

    #expect(rows.map(\.name) == ["barely"])
  }

  @Test("A group whose processes sum past the floor is kept")
  func groupSumClearsFloor() {
    let app = Self.group("com.example.app", name: "Example", pids: [20, 21])
    let rows = GPUUsageBuilder.build(
      percentByPID: [20: 0.03, 21: 0.03], groups: [app], fallbackNamesByPID: [:], limit: 10)

    #expect(rows.map(\.name) == ["Example"])
  }

  @Test("Order is percent descending, then name, then key")
  func ordering() {
    let rows = GPUUsageBuilder.build(
      percentByPID: [3: 5, 1: 9, 2: 5, 4: 5], groups: [],
      fallbackNamesByPID: [1: "Zed", 2: "beta", 3: "Alpha", 4: "beta"], limit: 10)

    #expect(rows.map(\.groupKey) == ["gpu-pid:1", "gpu-pid:3", "gpu-pid:2", "gpu-pid:4"])
  }

  @Test("Only the top rows up to the limit survive")
  func limit() {
    var percents: [Int32: Double] = [:]
    for pid in 1...12 { percents[Int32(pid)] = Double(pid) }
    let rows = GPUUsageBuilder.build(
      percentByPID: percents, groups: [], fallbackNamesByPID: [:], limit: 10)

    #expect(rows.count == 10)
    #expect(rows.first?.gpuPercent == 12)
    #expect(rows.last?.gpuPercent == 3)
  }
}
