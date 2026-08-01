struct PortGroup: Sendable, Equatable, Identifiable {
  let groupKey: String
  let name: String
  let bundleIdentifier: String?
  let representativePID: Int32
  /// Sorted ascending, tcp before udp on ties.
  let ports: [ListeningPort]
  /// Present for same-user rows; carries the children ProcessTerminator
  /// needs. nil marks a system row: no quit affordance, generic icon.
  let appGroup: AppGroup?

  var id: String { groupKey }
  var isSystem: Bool { appGroup == nil }
}
