/// Consolidates a flat process list into per-application groups. Pure and
/// fixture-testable: no NSWorkspace or syscalls here, only the plain data
/// SamplerService and the live app-metadata lookup already produced.
///
/// Resolution order per process:
/// 1. Direct app metadata for this pid.
/// 2. Walk the parent chain to the nearest ancestor with app metadata.
/// 3. Strip a " Helper" suffix and match a currently running app by name.
/// 4. Stand alone as a single-process group.
enum GroupingEngine {
  static func group(
    measurements: [ProcessMeasurement],
    metadataByPID: [Int32: AppMetadata]
  ) -> [AppGroup] {
    let snapshotsByPID = Dictionary(
      uniqueKeysWithValues: measurements.map { ($0.snapshot.pid, $0.snapshot) }
    )

    var childrenByGroupKey: [String: [ProcessMeasurement]] = [:]
    var identityByGroupKey: [String: (name: String, bundleIdentifier: String?, pid: Int32)] = [:]
    var groupOrder: [String] = []

    for measurement in measurements {
      let identity = resolveIdentity(
        for: measurement.snapshot,
        snapshotsByPID: snapshotsByPID,
        metadataByPID: metadataByPID
      )
      if childrenByGroupKey[identity.key] == nil {
        groupOrder.append(identity.key)
        identityByGroupKey[identity.key] = (identity.name, identity.bundleIdentifier, identity.pid)
      }
      childrenByGroupKey[identity.key, default: []].append(measurement)
    }

    return groupOrder.compactMap { key -> AppGroup? in
      guard
        let identity = identityByGroupKey[key],
        let children = childrenByGroupKey[key]
      else {
        return nil
      }
      let sortedChildren = children.sorted { lhs, rhs in
        (lhs.cpuPercent ?? -1) > (rhs.cpuPercent ?? -1)
      }
      let cpuPercent = summedCPUPercent(of: sortedChildren)
      let memoryBytes = sortedChildren.reduce(UInt64(0)) { $0 + $1.snapshot.memoryBytes }

      return AppGroup(
        groupKey: key,
        name: identity.name,
        bundleIdentifier: identity.bundleIdentifier,
        representativePID: identity.pid,
        cpuPercent: cpuPercent,
        memoryBytes: memoryBytes,
        children: sortedChildren
      )
    }
  }

  /// Deterministic top-N ordering: primary metric descending, then name
  /// ascending so equal-valued groups never reorder from run to run.
  /// Groups with no reading yet are excluded, not ranked: a nil metric is
  /// unknown, not zero, and ranking unknowns once filled the CPU list with
  /// an alphabetical placeholder top-10 on the priming tick.
  static func topGroups(
    from groups: [AppGroup],
    by metric: (AppGroup) -> Double?,
    limit: Int
  ) -> [AppGroup] {
    groups
      .compactMap { group in metric(group).map { (group: group, value: $0) } }
      .sorted { lhs, rhs in
        if lhs.value != rhs.value {
          return lhs.value > rhs.value
        }
        return lhs.group.name.localizedStandardCompare(rhs.group.name) == .orderedAscending
      }
      .prefix(limit)
      .map(\.group)
  }

  private static func summedCPUPercent(of measurements: [ProcessMeasurement]) -> Double? {
    let values = measurements.compactMap(\.cpuPercent)
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +)
  }

  private static func resolveIdentity(
    for snapshot: ProcessSnapshot,
    snapshotsByPID: [Int32: ProcessSnapshot],
    metadataByPID: [Int32: AppMetadata]
  ) -> (key: String, name: String, bundleIdentifier: String?, pid: Int32) {
    if let metadata = metadataByPID[snapshot.pid] {
      return (groupKey(for: metadata), metadata.name, metadata.bundleIdentifier, metadata.pid)
    }

    if let ancestorMetadata = resolveViaAncestry(from: snapshot, snapshotsByPID: snapshotsByPID, metadataByPID: metadataByPID) {
      return (
        groupKey(for: ancestorMetadata), ancestorMetadata.name, ancestorMetadata.bundleIdentifier,
        ancestorMetadata.pid
      )
    }

    if let strippedName = strippingHelperSuffix(snapshot.name) {
      if let match = metadataByPID.values.first(where: { $0.name == strippedName }) {
        return (groupKey(for: match), match.name, match.bundleIdentifier, match.pid)
      }
      return ("name:\(strippedName)", strippedName, nil, snapshot.pid)
    }

    return ("pid:\(snapshot.pid)", snapshot.name, nil, snapshot.pid)
  }

  private static func resolveViaAncestry(
    from snapshot: ProcessSnapshot,
    snapshotsByPID: [Int32: ProcessSnapshot],
    metadataByPID: [Int32: AppMetadata]
  ) -> AppMetadata? {
    var currentPID = snapshot.pid
    var visited: Set<Int32> = []

    while let current = snapshotsByPID[currentPID], !visited.contains(currentPID) {
      visited.insert(currentPID)
      let parentPID = current.parentPID
      if let parentMetadata = metadataByPID[parentPID] {
        return parentMetadata
      }
      currentPID = parentPID
    }
    return nil
  }

  private static func groupKey(for metadata: AppMetadata) -> String {
    metadata.bundleIdentifier ?? "pid:\(metadata.pid)"
  }

  private static func strippingHelperSuffix(_ name: String) -> String? {
    guard let range = name.range(of: " Helper") else { return nil }
    return String(name[..<range.lowerBound])
  }
}
