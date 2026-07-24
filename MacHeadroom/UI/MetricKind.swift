enum MetricKind: String, CaseIterable, Identifiable {
  case cpu = "CPU"
  case memory = "Memory"

  var id: String { rawValue }

  func value(of group: AppGroup) -> Double? {
    switch self {
    case .cpu: group.cpuPercent
    case .memory: Double(group.memoryBytes)
    }
  }
}
