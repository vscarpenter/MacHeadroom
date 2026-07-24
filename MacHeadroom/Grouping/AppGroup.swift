struct AppGroup: Sendable, Equatable, Identifiable {
  let groupKey: String
  let name: String
  let bundleIdentifier: String?
  let representativePID: Int32
  let cpuPercent: Double?
  let memoryBytes: UInt64
  let children: [ProcessMeasurement]

  var id: String { groupKey }
  var processCount: Int { children.count }
}
