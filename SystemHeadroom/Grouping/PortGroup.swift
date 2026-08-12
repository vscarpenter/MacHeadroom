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

  /// Namespaced so a port row's identity can never equal an AppGroup's:
  /// both row kinds live in one LazyVStack per popover skin, and the lazy
  /// container caches row views by explicit identity across tab switches —
  /// a colliding id resurrects the other tab's cached row.
  var id: String { "port:\(groupKey)" }
  var isSystem: Bool { appGroup == nil }
}
