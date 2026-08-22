import AppKit
import SwiftUI

struct GroupRowView: View {
  let group: AppGroup
  let metric: MetricKind
  let maxValue: Double
  let store: MonitorStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isExpanded = false
  @State private var isRowHovered = false

  private var value: Double? { metric.value(of: group) }
  private var ratio: Double {
    guard let value, maxValue > 0 else { return 0 }
    return min(max(value / maxValue, 0), 1)
  }
  private var glossaryEntry: ProcessGlossary.Entry? { ProcessGlossary.entry(for: group) }

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

        if let entry = glossaryEntry {
          VStack(alignment: .leading, spacing: 1) {
            Text(entry.friendlyName)
              .lineLimit(1)
            Text(group.name)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        } else {
          Text(group.name)
            .lineLimit(1)
        }

        if group.processCount > 1 {
          Text("×\(group.processCount)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
        }

        Spacer()

        QuitAffordanceView(
          group: group, store: store,
          accent: .accentColor, secondary: .secondary,
          isRowHovered: isRowHovered
        ) {
          Text(
            ValueFormatting.value(
              metric, for: group, memoryMetric: store.processMemoryMetric))
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
        }
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
    .help(helpText)
    .quitContextMenu(for: group, store: store)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: value)
    .onHover { hovering in
      guard store.canTerminate else { return }
      withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
        isRowHovered = hovering
      }
    }

    if isExpanded {
      ForEach(group.children, id: \.snapshot.pid) { child in
        ChildRowView(
          measurement: child,
          metric: metric,
          memoryMetric: store.processMemoryMetric)
      }
    }
  }

  private var helpText: String {
    [
      glossaryEntry?.blurb,
      metric == .memory ? store.processMemoryMetric.helpText : nil,
    ]
    .compactMap { $0 }
    .joined(separator: "\n\n")
  }

  private var accessibilityLabel: String {
    let processWord = group.processCount == 1 ? "process" : "processes"
    let metricLabel =
      metric == .cpu ? "percent CPU" : store.processMemoryMetric.accessibilityName
    let name = glossaryEntry.map { "\($0.friendlyName), \(group.name)" } ?? group.name
    let value = ValueFormatting.value(
      metric, for: group, memoryMetric: store.processMemoryMetric)
    return "\(name), \(group.processCount) \(processWord), "
      + "\(value) \(metricLabel)"
  }
}

private struct ChildRowView: View {
  let measurement: ProcessMeasurement
  let metric: MetricKind
  let memoryMetric: ProcessMemoryMetric

  private var valueText: String {
    switch metric {
    case .cpu: ValueFormatting.percent(measurement.cpuPercent)
    case .memory:
      ValueFormatting.memory(measurement.snapshot.memoryBytes, metric: memoryMetric)
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
