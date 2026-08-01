import AppKit
import SwiftUI

/// The classic skin's Ports pane. Three states: unavailable (sysctl or
/// parse failure this tick), empty, rows. Rows are uniform height so the
/// pane's ideal height can never depend on content.
struct PortsPaneView: View {
  let store: MonitorStore

  var body: some View {
    if let rows = store.portGroups {
      if rows.isEmpty {
        Text("No listening ports")
          .foregroundStyle(.secondary)
          .padding(.vertical, 20)
      } else {
        ForEach(rows) { row in
          PortRowView(group: row, store: store)
        }
      }
    } else {
      Text("Ports unavailable")
        .foregroundStyle(.secondary)
        .padding(.vertical, 20)
    }
  }
}

struct PortRowView: View {
  let group: PortGroup
  let store: MonitorStore
  @State private var isRowHovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let maxBadges = 4

  var body: some View {
    HStack(spacing: 8) {
      Image(nsImage: icon)
        .resizable()
        .frame(width: 18, height: 18)

      Text(group.name)
        .lineLimit(1)

      if group.isSystem {
        Text("system")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(.quaternary, in: Capsule())
      }

      Spacer()

      if let appGroup = group.appGroup {
        QuitAffordanceView(
          group: appGroup, store: store,
          accent: .accentColor, secondary: .secondary,
          isRowHovered: isRowHovered
        ) {
          badges
        }
      } else {
        badges
      }
    }
    .frame(height: 26)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .onHover { hovering in
      guard store.canTerminate, group.appGroup != nil else { return }
      withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
        isRowHovered = hovering
      }
    }
  }

  private var badges: some View {
    HStack(spacing: 4) {
      ForEach(group.ports.prefix(Self.maxBadges), id: \.self) { port in
        PortBadge(port: port)
      }
      if group.ports.count > Self.maxBadges {
        Text("+\(group.ports.count - Self.maxBadges)")
          .font(.system(.caption2, design: .monospaced))
          .foregroundStyle(.secondary)
      }
    }
  }

  private var icon: NSImage {
    if let appGroup = group.appGroup {
      return AppIconProvider.icon(for: appGroup)
    }
    return NSImage(
      systemSymbolName: "gearshape.fill", accessibilityDescription: group.name)
      ?? NSImage()
  }

  private var accessibilityLabel: String {
    // String(port.number), never interpolation of the UInt16 directly:
    // port numbers must not pick up locale grouping separators.
    let portsText = group.ports
      .map { "\(String($0.number)) \($0.transport.rawValue.uppercased())" }
      .joined(separator: ", ")
    let origin = group.isSystem ? ", system process" : ""
    return "\(group.name)\(origin), listening on \(portsText)"
  }
}

struct PortBadge: View {
  let port: ListeningPort

  var body: some View {
    Text(port.transport == .udp ? "\(String(port.number)) udp" : String(port.number))
      .font(.system(.caption2, design: .monospaced))
      .padding(.horizontal, 5)
      .padding(.vertical, 2)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
  }
}
