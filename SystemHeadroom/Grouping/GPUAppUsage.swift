/// One row of the GPU ranking: an app group, or a system process the
/// same-user process table cannot see.
struct GPUAppUsage: Sendable, Equatable, Identifiable {
  let groupKey: String
  let name: String
  let bundleIdentifier: String?
  let representativePID: Int32
  /// Share of wall time the GPU spent on this row's work.
  let gpuPercent: Double
  let processCount: Int
  /// Present for same-user rows; carries the children ProcessTerminator
  /// needs. nil marks a system row: no quit affordance, generic icon.
  let appGroup: AppGroup?

  /// Namespaced like PortGroup's id: row kinds share one LazyVStack per
  /// popover skin, and a colliding id resurrects another tab's cached row.
  var id: String { "gpu:\(groupKey)" }
  var isSystem: Bool { appGroup == nil }
}

/// Folds per-process GPU percents onto the app groups the popover
/// already shows. Pure and fixture-testable, like PortGroupBuilder.
enum GPUUsageBuilder {
  /// Below this a row would read "0.0%".
  static let floorPercent = 0.05

  /// The registry lists every GPU client on the machine, so a pid can
  /// belong to no group: root and other-user processes (WindowServer,
  /// for one) are outside the same-user process table. Those become
  /// system rows named from the registry. Row order: percent
  /// descending, then name, then key so ties never reorder.
  static func build(
    percentByPID: [Int32: Double],
    groups: [AppGroup],
    fallbackNamesByPID: [Int32: String],
    limit: Int
  ) -> [GPUAppUsage] {
    var groupByPID: [Int32: AppGroup] = [:]
    for group in groups {
      for child in group.children {
        groupByPID[child.snapshot.pid] = group
      }
    }

    var percentByKey: [String: Double] = [:]
    var groupsByKey: [String: AppGroup] = [:]
    var systemPIDByKey: [String: Int32] = [:]
    // Sorted so a group's percents always add in the same order;
    // floating-point sums otherwise differ in the last bit run to run.
    for (pid, percent) in percentByPID.sorted(by: { $0.key < $1.key }) {
      if let group = groupByPID[pid] {
        percentByKey[group.groupKey, default: 0] += percent
        groupsByKey[group.groupKey] = group
      } else {
        let key = "gpu-pid:\(pid)"
        percentByKey[key] = percent
        systemPIDByKey[key] = pid
      }
    }

    let rows = percentByKey.compactMap { key, percent -> GPUAppUsage? in
      guard percent >= floorPercent else { return nil }
      if let group = groupsByKey[key] {
        return GPUAppUsage(
          groupKey: key, name: group.name, bundleIdentifier: group.bundleIdentifier,
          representativePID: group.representativePID, gpuPercent: percent,
          processCount: group.processCount, appGroup: group)
      }
      guard let pid = systemPIDByKey[key] else { return nil }
      let registryName = fallbackNamesByPID[pid] ?? ""
      return GPUAppUsage(
        groupKey: key, name: registryName.isEmpty ? "pid \(pid)" : registryName,
        bundleIdentifier: nil, representativePID: pid, gpuPercent: percent,
        processCount: 1, appGroup: nil)
    }

    return Array(
      rows.sorted { lhs, rhs in
        if lhs.gpuPercent != rhs.gpuPercent { return lhs.gpuPercent > rhs.gpuPercent }
        let names = lhs.name.localizedStandardCompare(rhs.name)
        if names != .orderedSame { return names == .orderedAscending }
        return lhs.groupKey < rhs.groupKey
      }
      .prefix(limit))
  }
}
