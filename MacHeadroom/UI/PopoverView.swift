import SwiftUI

struct PopoverView: View {
  let store: MonitorStore
  @State private var selectedMetric: MetricKind = .cpu
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var groups: [AppGroup] {
    selectedMetric == .cpu ? store.topCPUGroups : store.topMemoryGroups
  }

  private var maxValue: Double {
    groups.first.flatMap { selectedMetric.value(of: $0) } ?? 0
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      list
      Divider()
      footer
    }
    .frame(width: 340)
    .background(.regularMaterial)
    .onAppear {
      store.popoverDidAppear()
    }
    .onDisappear {
      store.popoverDidDisappear()
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      Picker("Metric", selection: $selectedMetric) {
        ForEach(MetricKind.allCases) { metric in
          Text(metric.rawValue).tag(metric)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      HStack {
        Text("\(ValueFormatting.percent(store.systemSummary.cpuPercent)) CPU")
        Spacer()
        Text(
          "\(ValueFormatting.bytes(store.systemSummary.memoryUsedBytes)) of "
            + ValueFormatting.bytes(store.systemSummary.memoryTotalBytes)
        )
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(12)
  }

  private var list: some View {
    ScrollView {
      LazyVStack(spacing: 10) {
        if groups.isEmpty {
          Text("No data yet")
            .foregroundStyle(.secondary)
            .padding(.vertical, 20)
        } else {
          ForEach(groups) { group in
            GroupRowView(group: group, metric: selectedMetric, maxValue: maxValue)
          }
        }
      }
      .padding(12)
      .animation(reduceMotion ? nil : .default, value: groups)
    }
    // A fixed height, not maxHeight: the MenuBarExtra window sizes itself
    // once, at open, before the first sample lands. The ideal height must
    // not depend on list content or the rows arrive into zero space.
    .frame(height: 360)
  }

  private var footer: some View {
    HStack {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        Text(ValueFormatting.updatedAgo(since: store.lastUpdated, now: context.date))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button {
        Task { await store.refreshNow() }
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Refresh")

      SettingsLink {
        Image(systemName: "gearshape")
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Settings")

      Button {
        NSApp.terminate(nil)
      } label: {
        Image(systemName: "power")
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Quit Mac Headroom")
    }
    .padding(12)
  }
}

#if DEBUG
  #Preview("Popover - Light") {
    PopoverView(store: PreviewFixtures.makeStore())
      .preferredColorScheme(.light)
  }

  #Preview("Popover - Dark") {
    PopoverView(store: PreviewFixtures.makeStore())
      .preferredColorScheme(.dark)
  }
#endif
