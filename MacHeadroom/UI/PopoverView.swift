import SwiftUI

struct PopoverView: View {
  let store: MonitorStore
  @State private var selectedTab: PopoverTab
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(store: MonitorStore, initialTab: PopoverTab = .cpu) {
    self.store = store
    _selectedTab = State(initialValue: initialTab)
  }

  private var groups: [AppGroup] {
    selectedTab == .cpu ? store.topCPUGroups : store.topMemoryGroups
  }

  private var maxValue: Double {
    guard let metric = selectedTab.metricKind else { return 0 }
    return groups.first.flatMap { metric.value(of: $0) } ?? 0
  }

  var body: some View {
    Group {
      if store.usesPorcelainAppearance {
        PorcelainPopoverView(store: store, initialTab: selectedTab)
      } else {
        standardPopover
      }
    }
    .frame(width: store.usesPorcelainAppearance ? 460 : 340)
    .onAppear {
      store.popoverDidAppear()
    }
    .onDisappear {
      store.popoverDidDisappear()
    }
  }

  private var standardPopover: some View {
    VStack(spacing: 0) {
      header
      Divider()
      list
      Divider()
      footer
    }
    .background(.regularMaterial)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      Picker("Metric", selection: $selectedTab) {
        ForEach(PopoverTab.allCases) { tab in
          Text(tab.rawValue).tag(tab)
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
        if let metric = selectedTab.metricKind {
          if groups.isEmpty {
            Text("No data yet")
              .foregroundStyle(.secondary)
              .padding(.vertical, 20)
          } else {
            ForEach(groups) { group in
              GroupRowView(group: group, metric: metric, maxValue: maxValue, store: store)
            }
          }
        } else {
          PortsPaneView(store: store)
        }
      }
      .padding(12)
      .animation(reduceMotion ? nil : .default, value: groups)
      .animation(reduceMotion ? nil : .default, value: store.portGroups)
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
      .accessibilityLabel("Quit Headroom Monitor")
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

  #Preview("Porcelain Native - Light") {
    PopoverView(store: PreviewFixtures.makeStore())
      .preferredColorScheme(.light)
  }

  #Preview("Porcelain Native - Dark") {
    PopoverView(store: PreviewFixtures.makeStore())
      .preferredColorScheme(.dark)
  }

  #Preview("Classic Compact") {
    PopoverView(store: PreviewFixtures.makeStore(usesPorcelainAppearance: false))
      .preferredColorScheme(.light)
  }
#endif
