enum PopoverTab: String, CaseIterable, Identifiable {
  case cpu = "CPU"
  case memory = "Memory"
  case gpu = "GPU"
  case drives = "Drives"
  case ports = "Ports"

  var id: String { rawValue }

  /// nil for the tabs that are not a CPU or memory ranking. Each of
  /// those draws its own pane.
  var metricKind: MetricKind? {
    switch self {
    case .cpu: .cpu
    case .memory: .memory
    case .gpu, .drives, .ports: nil
    }
  }
}
