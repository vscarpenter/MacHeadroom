import AppKit
import SwiftUI

// The classic skin's GPU and Drives panes. Each has three states:
// waiting for the first sample, unavailable on this Mac, and rows.
// They sit inside the list's fixed-height scroll region, so the
// popover's ideal height never depends on what they hold.

/// One stat row: icon, title over detail, value, and a used-share bar
/// when the row has one.
struct StatRowView: View {
  let row: StatRow

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Image(systemName: row.symbol)
          .foregroundStyle(.secondary)
          .frame(width: 18, height: 18)

        VStack(alignment: .leading, spacing: 1) {
          Text(row.title)
            .lineLimit(1)
          Text(row.subtitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        Spacer(minLength: 8)

        // Proportional with tabular digits, not the ranking rows'
        // monospace: these values carry words ("free", "MB/s"), and at
        // 340 points the monospaced width truncated the detail line.
        Text(row.value)
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .fixedSize()
      }

      if let usedFraction = row.usedFraction {
        UsedShareBar(fraction: usedFraction)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(row.accessibilityLabel)
  }
}

/// The classic bar every ranking row already draws, here as a share of
/// a known whole.
private struct UsedShareBar: View {
  let fraction: Double

  var body: some View {
    Capsule()
      .fill(.tertiary)
      .frame(height: 3)
      .overlay(alignment: .leading) {
        GeometryReader { proxy in
          Capsule()
            .fill(Color.accentColor)
            .frame(width: proxy.size.width * min(max(fraction, 0), 1))
        }
      }
  }
}

struct GPUPaneView: View {
  let store: MonitorStore

  var body: some View {
    switch GPUPresentation.paneState(gpu: store.gpu, hasSampled: store.lastUpdated != nil) {
    case .waiting:
      PaneMessage("No data yet")
    case .unavailable:
      PaneMessage("GPU statistics unavailable")
    case .ready:
      if let gpu = store.gpu {
        ForEach(
          GPUPresentation.statRows(
            gpu, installedMemoryBytes: store.systemSummary.memoryTotalBytes)
        ) { row in
          StatRowView(row: row)
        }

        Text("Top GPU apps")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 4)
          .accessibilityAddTraits(.isHeader)

        ranking
      }
    }
  }

  /// nil means the counters have no delta yet; empty means nothing is
  /// drawing on the GPU.
  @ViewBuilder
  private var ranking: some View {
    if let apps = store.topGPUApps {
      if apps.isEmpty {
        PaneMessage("No GPU activity")
      } else {
        ForEach(apps) { usage in
          GPUAppRowView(usage: usage, maxValue: apps.first?.gpuPercent ?? 0, store: store)
        }
      }
    } else {
      PaneMessage("Measuring…")
    }
  }
}

struct DrivesPaneView: View {
  let store: MonitorStore
  @Environment(\.locale) private var locale

  var body: some View {
    switch DrivesPresentation.paneState(
      volumes: store.volumes, hasSampled: store.lastUpdated != nil)
    {
    case .waiting:
      PaneMessage("No data yet")
    case .unavailable:
      PaneMessage("Drives unavailable")
    case .ready:
      ForEach(
        DrivesPresentation.rows(
          volumes: store.volumes, activity: store.diskActivity, health: store.driveHealth,
          locale: locale)
      ) { row in
        StatRowView(row: row)
      }
    }
  }
}

private struct PaneMessage: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .foregroundStyle(.secondary)
      .padding(.vertical, 20)
  }
}

/// One row of the GPU ranking. App rows carry the same hover-quit
/// affordance and context menu as CPU and Memory rows; system rows,
/// which the same-user process table cannot see, carry neither.
struct GPUAppRowView: View {
  let usage: GPUAppUsage
  let maxValue: Double
  let store: MonitorStore
  @State private var isRowHovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var ratio: Double {
    guard maxValue > 0 else { return 0 }
    return min(max(usage.gpuPercent / maxValue, 0), 1)
  }

  /// Matches StatRowView's value above it in the same pane.
  private var valueText: some View {
    Text(ValueFormatting.percent(usage.gpuPercent))
      .monospacedDigit()
      .foregroundStyle(.secondary)
  }

  var body: some View {
    if let appGroup = usage.appGroup {
      row {
        QuitAffordanceView(
          group: appGroup, store: store,
          accent: .accentColor, secondary: .secondary,
          isRowHovered: isRowHovered
        ) {
          valueText
        }
      }
      .quitContextMenu(for: appGroup, store: store)
      .onHover { hovering in
        guard store.canTerminate else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
          isRowHovered = hovering
        }
      }
    } else {
      row { valueText }
    }
  }

  private func row<Value: View>(@ViewBuilder value: () -> Value) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Image(nsImage: GPUAppRowPresentation.icon(for: usage))
          .resizable()
          .frame(width: 18, height: 18)

        Text(usage.name)
          .lineLimit(1)

        if usage.isSystem {
          Text("system")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
        }

        Spacer(minLength: 8)

        value()
      }

      UsedShareBar(fraction: ratio)
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(GPUAppRowPresentation.accessibilityLabel(for: usage))
  }
}

/// Icon and spoken label for a GPU ranking row, shared by both skins.
enum GPUAppRowPresentation {
  @MainActor
  static func icon(for usage: GPUAppUsage) -> NSImage {
    if let appGroup = usage.appGroup {
      return AppIconProvider.icon(for: appGroup)
    }
    return NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: usage.name)
      ?? NSImage()
  }

  static func accessibilityLabel(for usage: GPUAppUsage) -> String {
    let origin = usage.isSystem ? ", system process" : ""
    return "\(usage.name)\(origin), \(ValueFormatting.percent(usage.gpuPercent)) of GPU time"
  }
}
