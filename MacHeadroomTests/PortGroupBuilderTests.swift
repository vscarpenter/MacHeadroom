import Testing

@testable import MacHeadroom

@Suite("Port group builder")
struct PortGroupBuilderTests {
  private func measurement(pid: Int32, name: String) -> ProcessMeasurement {
    ProcessMeasurement(
      snapshot: ProcessSnapshot(
        pid: pid, parentPID: 1, userID: 501, name: name,
        startIdentity: "\(pid):0", cpuTimeTicks: 0, residentBytes: 0),
      cpuPercent: nil)
  }

  private func appGroup(key: String, name: String, pids: [Int32]) -> AppGroup {
    AppGroup(
      groupKey: key, name: name, bundleIdentifier: nil,
      representativePID: pids[0], cpuPercent: nil, memoryBytes: 0,
      children: pids.map { measurement(pid: $0, name: name) })
  }

  private func tcp(_ port: UInt16, pid: Int32) -> SocketRecord {
    SocketRecord(
      transport: .tcp, portNumber: port, pid: pid, effectivePid: 0,
      tcpState: MH_TCPS_LISTEN)
  }

  @Test("Helper pids fold their ports into the owning app's row")
  func helperPortsFold() throws {
    let node = appGroup(key: "pid:100", name: "node", pids: [100, 101])
    let rows = try #require(
      PortGroupBuilder.build(
        sockets: [tcp(3000, pid: 100), tcp(5173, pid: 101)],
        groups: [node], fallbackNamesByPID: [:]))
    #expect(rows.count == 1)
    #expect(rows[0].ports == [
      ListeningPort(number: 3000, transport: .tcp),
      ListeningPort(number: 5173, transport: .tcp),
    ])
    #expect(rows[0].appGroup == node)
  }

  @Test("Groups with no listening sockets are dropped")
  func silentGroupsDropped() throws {
    let idle = appGroup(key: "pid:200", name: "idle", pids: [200])
    let rows = try #require(
      PortGroupBuilder.build(sockets: [], groups: [idle], fallbackNamesByPID: [:]))
    #expect(rows.isEmpty)
  }

  @Test("Root listeners become system rows named from the fallback map")
  func rootFallbackRow() throws {
    let rows = try #require(
      PortGroupBuilder.build(
        sockets: [tcp(445, pid: 88)], groups: [], fallbackNamesByPID: [88: "smbd"]))
    #expect(rows.count == 1)
    #expect(rows[0].isSystem)
    #expect(rows[0].name == "smbd")
    #expect(rows[0].representativePID == 88)
  }

  @Test("A vanished owner with no name still gets a row, labeled by pid")
  func vanishedOwnerLabeledByPid() throws {
    let rows = try #require(
      PortGroupBuilder.build(
        sockets: [tcp(8080, pid: 999)], groups: [], fallbackNamesByPID: [:]))
    #expect(rows[0].name == "pid 999")
  }

  @Test("Duplicate ports from one owner dedupe; sort is user rows then system, by name")
  func orderingAndDedupe() throws {
    let zsh = appGroup(key: "pid:300", name: "zsh", pids: [300])
    let node = appGroup(key: "pid:100", name: "node", pids: [100])
    let rows = try #require(
      PortGroupBuilder.build(
        sockets: [
          tcp(3000, pid: 100), tcp(3000, pid: 100), tcp(9000, pid: 300),
          tcp(445, pid: 88),
        ],
        groups: [zsh, node], fallbackNamesByPID: [88: "smbd"]))
    #expect(rows.map(\.name) == ["node", "zsh", "smbd"])
    #expect(rows[0].ports == [ListeningPort(number: 3000, transport: .tcp)])
  }

  @Test("nil sockets propagate as nil")
  func nilPropagates() {
    #expect(
      PortGroupBuilder.build(sockets: nil, groups: [], fallbackNamesByPID: [:]) == nil)
  }

  @Test("Port row identity never collides with the owning app group's identity")
  func idDisjointFromAppGroupID() throws {
    // Both popover skins render the metric rows and the port rows inside one
    // shared LazyVStack, which caches row views by explicit ForEach identity
    // across tab switches. An app present in both lists with a colliding id
    // gets the stale cached row from the other tab.
    let node = appGroup(key: "pid:100", name: "node", pids: [100])
    let rows = try #require(
      PortGroupBuilder.build(
        sockets: [tcp(3000, pid: 100)], groups: [node], fallbackNamesByPID: [:]))
    #expect(rows[0].id != node.id)
  }
}
