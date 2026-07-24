import AppKit
import SwiftUI

struct GroupRowView: View {
  let group: AppGroup
  let metric: MetricKind
  let maxValue: Double
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isExpanded = false

  private var value: Double? { metric.value(of: group) }
  private var ratio: Double {
    guard let value, maxValue > 0 else { return 0 }
    return min(max(value / maxValue, 0), 1)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        if group.processCount > 1 {
          Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
              isExpanded.toggle()
            }
          } label: {
            Image(systemName: "chevron.right")
              .rotationEffect(.degrees(isExpanded ? 90 : 0))
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
        } else {
          Color.clear.frame(width: 10)
        }

        Image(nsImage: AppIconProvider.icon(for: group))
          .resizable()
          .frame(width: 18, height: 18)

        Text(group.name)
          .lineLimit(1)

        if group.processCount > 1 {
          Text("×\(group.processCount)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
        }

        Spacer()

        Text(ValueFormatting.value(metric, for: group))
          .font(.system(.body, design: .monospaced))
          .foregroundStyle(.secondary)
      }

      Capsule()
        .fill(.tertiary)
        .frame(height: 3)
        .overlay(alignment: .leading) {
          GeometryReader { proxy in
            Capsule()
              .fill(Color.accentColor)
              .frame(width: proxy.size.width * ratio)
          }
        }
        .padding(.leading, group.processCount > 1 ? 18 : 0)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: value)

    if isExpanded {
      ForEach(group.children, id: \.snapshot.pid) { child in
        ChildRowView(measurement: child, metric: metric)
      }
    }
  }

  private var accessibilityLabel: String {
    let processWord = group.processCount == 1 ? "process" : "processes"
    let metricLabel = metric == .cpu ? "percent CPU" : "memory"
    return "\(group.name), \(group.processCount) \(processWord), "
      + "\(ValueFormatting.value(metric, for: group)) \(metricLabel)"
  }
}

private struct ChildRowView: View {
  let measurement: ProcessMeasurement
  let metric: MetricKind

  private var valueText: String {
    switch metric {
    case .cpu: ValueFormatting.percent(measurement.cpuPercent)
    case .memory: ValueFormatting.bytes(measurement.snapshot.residentBytes)
    }
  }

  var body: some View {
    HStack(spacing: 8) {
      Color.clear.frame(width: 28)
      Text(measurement.snapshot.name)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer()
      Text(valueText)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(measurement.snapshot.name), \(valueText)")
  }
}

enum AppIconProvider {
  static func icon(for group: AppGroup) -> NSImage {
    if let bundleIdentifier = group.bundleIdentifier,
      let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .first,
      let icon = app.icon
    {
      return icon
    }
    if let app = NSRunningApplication(processIdentifier: group.representativePID),
      let icon = app.icon
    {
      return icon
    }
    return NSImage(
      systemSymbolName: "gearshape.fill", accessibilityDescription: group.name)
      ?? NSImage()
  }
}
