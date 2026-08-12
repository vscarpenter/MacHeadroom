/// Folds listening sockets onto the app groups the popover already
/// shows. Pure and fixture-testable, like GroupingEngine: no syscalls,
/// no NSWorkspace.
enum PortGroupBuilder {
  /// nil in → nil out (ports unavailable). Groups whose pids own no
  /// listening socket are dropped. Row order: same-user rows first,
  /// then system rows; localizedStandardCompare on name within each,
  /// groupKey as the final tiebreaker so equal names never reorder
  /// from run to run.
  static func build(
    sockets: [SocketRecord]?,
    groups: [AppGroup],
    fallbackNamesByPID: [Int32: String]
  ) -> [PortGroup]? {
    guard let sockets else { return nil }

    var groupKeyByPID: [Int32: String] = [:]
    var groupsByKey: [String: AppGroup] = [:]
    for group in groups {
      groupsByKey[group.groupKey] = group
      for child in group.children {
        groupKeyByPID[child.snapshot.pid] = group.groupKey
      }
    }

    var portsByRowKey: [String: Set<ListeningPort>] = [:]
    var systemRowInfo: [String: (name: String, pid: Int32)] = [:]
    for record in sockets {
      let port = ListeningPort(number: record.portNumber, transport: record.transport)
      if let key = groupKeyByPID[record.pid] {
        portsByRowKey[key, default: []].insert(port)
      } else {
        let key = "port-pid:\(record.pid)"
        portsByRowKey[key, default: []].insert(port)
        systemRowInfo[key] = (
          fallbackNamesByPID[record.pid] ?? "pid \(record.pid)", record.pid
        )
      }
    }

    let rows = portsByRowKey.map { key, ports -> PortGroup in
      if let group = groupsByKey[key] {
        return PortGroup(
          groupKey: key, name: group.name,
          bundleIdentifier: group.bundleIdentifier,
          representativePID: group.representativePID,
          ports: ports.sorted(), appGroup: group)
      }
      // systemRowInfo always has this key by construction; the fallback
      // tuple only guards against an impossible miss.
      let info = systemRowInfo[key] ?? ("pid \(key)", 0)
      return PortGroup(
        groupKey: key, name: info.name, bundleIdentifier: nil,
        representativePID: info.pid, ports: ports.sorted(), appGroup: nil)
    }

    return rows.sorted { lhs, rhs in
      if lhs.isSystem != rhs.isSystem { return !lhs.isSystem }
      let names = lhs.name.localizedStandardCompare(rhs.name)
      if names != .orderedSame { return names == .orderedAscending }
      return lhs.groupKey < rhs.groupKey
    }
  }
}
