enum PopoverTab: String, CaseIterable, Identifiable {
  case cpu = "CPU"
  case memory = "Memory"
  case ports = "Ports"

  var id: String { rawValue }

  /// nil for .ports — the ports pane is not a metric ranking.
  var metricKind: MetricKind? {
    switch self {
    case .cpu: .cpu
    case .memory: .memory
    case .ports: nil
    }
  }
}
