import AppKit
import SwiftUI

struct PorcelainPopoverView: View {
  let store: MonitorStore
  @State private var selectedTab: PopoverTab
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme

  init(store: MonitorStore, initialTab: PopoverTab = .cpu) {
    self.store = store
    _selectedTab = State(initialValue: initialTab)
  }

  private var palette: PorcelainPalette {
    PorcelainPalette(colorScheme: colorScheme)
  }

  private var groups: [AppGroup] {
    selectedTab == .cpu ? store.topCPUGroups : store.topMemoryGroups
  }

  private var maxValue: Double {
    guard let metric = selectedTab.metricKind else { return 0 }
    return groups.first.flatMap { metric.value(of: $0) } ?? 0
  }

  private var headerTitle: String {
    selectedTab == .ports ? "Local ports" : "\(selectedTab.rawValue) headroom"
  }

  /// The header's big number: headroom percent for the metric tabs,
  /// total listening-port count for the ports tab, nil when unknown.
  private var headlineNumber: Int? {
    switch selectedTab {
    case .cpu:
      ValueFormatting.headroomPercent(
        used: store.systemSummary.cpuPercent,
        capacity: 100
      )
    case .memory:
      ValueFormatting.headroomPercent(
        used: Double(store.systemSummary.memoryUsedBytes),
        capacity: Double(store.systemSummary.memoryTotalBytes)
      )
    case .ports:
      store.portGroups.map { $0.reduce(0) { $0 + $1.ports.count } }
    }
  }

  private var headlineText: String {
    headlineNumber.map(String.init) ?? "—"
  }

  private var headlineAccessibilityLabel: String {
    switch selectedTab {
    case .cpu, .memory:
      return headlineNumber.map { "\($0) percent \(selectedTab.rawValue) headroom" }
        ?? "\(selectedTab.rawValue) headroom unavailable"
    case .ports:
      return headlineNumber.map { "\($0) listening ports" } ?? "Ports unavailable"
    }
  }

  private var usageDetail: String {
    switch selectedTab {
    case .cpu:
      let cpu = ValueFormatting.percent(store.systemSummary.cpuPercent)
      return "\(cpu) in use · "
        + "\(ValueFormatting.bytes(store.systemSummary.memoryUsedBytes)) of "
        + ValueFormatting.bytes(store.systemSummary.memoryTotalBytes)
    case .memory:
      return "\(ValueFormatting.bytes(store.systemSummary.memoryUsedBytes)) in use · "
        + "\(ValueFormatting.bytes(store.systemSummary.memoryTotalBytes)) total"
    case .ports:
      guard let rows = store.portGroups else { return "Ports unavailable" }
      let processWord = rows.count == 1 ? "process" : "processes"
      return "\(rows.count) \(processWord) listening"
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      porcelainDivider
      list
      porcelainDivider
      footer
    }
    .background(palette.canvas)
    .foregroundStyle(palette.textPrimary)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: PorcelainSpacing.md) {
      Capsule()
        .fill(palette.accent)
        .frame(width: 38, height: 3)
        .accessibilityHidden(true)

      HStack(alignment: .center, spacing: PorcelainSpacing.lg) {
        VStack(alignment: .leading, spacing: PorcelainSpacing.sm) {
          Text(headerTitle)
            .font(.system(size: 20, weight: .regular))

          HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(headlineText)
              .font(.system(size: 54, weight: .regular, design: .rounded))
              .monospacedDigit()
              .contentTransition(.numericText())

            if headlineNumber != nil, selectedTab != .ports {
              Text("%")
                .font(.system(size: 30, weight: .regular, design: .rounded))
            }
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel(headlineAccessibilityLabel)

          Text(usageDetail)
            .font(.system(size: 13))
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
        }

        Spacer(minLength: 0)

        PorcelainMetricPicker(selection: $selectedTab, palette: palette)
          .frame(width: 240)
      }
    }
    .padding(.horizontal, PorcelainSpacing.lg)
    .padding(.top, PorcelainSpacing.lg)
    .padding(.bottom, PorcelainSpacing.md)
    .frame(height: 172, alignment: .topLeading)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selectedTab)
  }

  private var list: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        if let metric = selectedTab.metricKind {
          if groups.isEmpty {
            emptyState(
              icon: "waveform.path", title: "Waiting for a signal…",
              detail: "The first sample will appear in a moment.")
          } else {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
              PorcelainGroupRowView(
                group: group,
                metric: metric,
                maxValue: maxValue,
                isTopConsumer: index == 0,
                palette: palette,
                store: store
              )

              if group.id != groups.last?.id {
                porcelainRowDivider
              }
            }
          }
        } else if let rows = store.portGroups {
          if rows.isEmpty {
            emptyState(
              icon: "app.connected.to.app.below.fill", title: "No listening ports",
              detail: "Nothing is serving on this Mac right now.")
          } else {
            ForEach(rows) { row in
              PorcelainPortRowView(group: row, palette: palette, store: store)

              if row.id != rows.last?.id {
                porcelainRowDivider
              }
            }
          }
        } else {
          emptyState(
            icon: "exclamationmark.triangle", title: "Ports unavailable",
            detail: "The port tables could not be read this sample.")
        }
      }
      .padding(.horizontal, PorcelainSpacing.lg)
      .padding(.vertical, PorcelainSpacing.xs)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: groups)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.portGroups)
    }
    // MenuBarExtra(.window) fixes its size at presentation time. Keep this
    // independent of list contents so the first live sample cannot collapse it.
    .frame(height: 468)
  }

  private var porcelainRowDivider: some View {
    Rectangle()
      .fill(palette.borderSubtle)
      .frame(height: 1)
      .padding(.leading, 48)
  }

  private func emptyState(icon: String, title: String, detail: String) -> some View {
    VStack(spacing: PorcelainSpacing.sm) {
      Image(systemName: icon)
        .font(.title3)
      Text(title)
        .font(.system(size: 13, weight: .medium))
      Text(detail)
        .font(.caption)
        .foregroundStyle(palette.textSecondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 52)
  }

  private var footer: some View {
    HStack(spacing: PorcelainSpacing.sm) {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        Text(ValueFormatting.updatedAgo(since: store.lastUpdated, now: context.date))
          .font(.caption)
          .foregroundStyle(palette.textSecondary)
      }

      Spacer()

      Button {
        Task { await store.refreshNow() }
      } label: {
        Image(systemName: "arrow.clockwise")
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.plain)
      .foregroundStyle(palette.textPrimary)
      .help("Refresh")
      .accessibilityLabel("Refresh")

      Menu {
        SettingsLink {
          Label("Settings", systemImage: "gearshape")
        }

        Divider()

        Button {
          NSApp.terminate(nil)
        } label: {
          Label("Quit Headroom Monitor", systemImage: "power")
        }
      } label: {
        Image(systemName: "ellipsis.circle")
          .frame(width: 24, height: 24)
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .foregroundStyle(palette.textPrimary)
      .help("More")
      .accessibilityLabel("More options")
    }
    .padding(.horizontal, PorcelainSpacing.lg)
    .padding(.vertical, PorcelainSpacing.sm)
  }

  private var porcelainDivider: some View {
    Rectangle()
      .fill(palette.borderSubtle)
      .frame(height: 1)
  }
}

private struct PorcelainMetricPicker: View {
  @Binding var selection: PopoverTab
  let palette: PorcelainPalette

  var body: some View {
    HStack(spacing: 0) {
      ForEach(PopoverTab.allCases) { metric in
        Button {
          selection = metric
        } label: {
          Text(metric.rawValue)
            .font(.system(size: 13, weight: selection == metric ? .semibold : .regular))
            .foregroundStyle(selection == metric ? palette.accent : palette.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background {
              if selection == metric {
                RoundedRectangle(cornerRadius: 8)
                  .fill(palette.controlSelected)
                  .overlay {
                    RoundedRectangle(cornerRadius: 8)
                      .stroke(palette.controlBorder, lineWidth: 1)
                  }
                  .shadow(color: palette.controlShadowAmbient, radius: 4, y: 2)
                  .shadow(color: palette.controlShadowDirect, radius: 1, y: 1)
              }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(metric.rawValue)
        .accessibilityValue(selection == metric ? "Selected" : "")
      }
    }
    .padding(4)
    .background(
      palette.controlTrack,
      in: RoundedRectangle(cornerRadius: 11)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 11)
        .stroke(palette.borderSubtle, lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Metric")
  }
}

private struct PorcelainGroupRowView: View {
  let group: AppGroup
  let metric: MetricKind
  let maxValue: Double
  let isTopConsumer: Bool
  let palette: PorcelainPalette
  let store: MonitorStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isExpanded = false
  @State private var isRowHovered = false

  private var value: Double? { metric.value(of: group) }

  private var ratio: Double {
    guard let value, maxValue > 0 else { return 0 }
    let visualScaleMaximum = maxValue * 1.6
    return min(max(value / visualScaleMaximum, 0), 1)
  }

  private var glossaryEntry: ProcessGlossary.Entry? {
    ProcessGlossary.entry(for: group)
  }

  private var subtitle: String {
    if glossaryEntry != nil {
      return group.name
    }
    let processWord = group.processCount == 1 ? "process" : "processes"
    return "\(group.processCount) \(processWord)"
  }

  var body: some View {
    VStack(spacing: 0) {
      rowControl
        .quitContextMenu(for: group, store: store)

      if isExpanded {
        ForEach(group.children, id: \.snapshot.pid) { child in
          PorcelainChildRowView(
            measurement: child,
            metric: metric,
            palette: palette
          )
        }
      }
    }
  }

  @ViewBuilder
  private var rowControl: some View {
    if group.processCount > 1 {
      // .contain groups the expand button and the chevron button into one
      // row-level VoiceOver entry point while still letting each be reached
      // and activated individually — unlike .combine, which would flatten
      // them into a single non-interactive element.
      expandableRowContent
        .accessibilityElement(children: .contain)
    } else {
      rowContent
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }
  }

  /// Multi-process row: the icon/title/spacer core toggles expand/collapse
  /// inside its own button, the chevron is a second small button doing the
  /// same toggle (mirroring `GroupRowView`), and the value text sits between
  /// them outside any button so `QuitAffordanceView` never nests a button
  /// inside a button. A row-level tap gesture restores the full-row expand
  /// target the padded row had before the quit affordance was added: inner
  /// buttons (rowCore, chevron, and the Direct build's quit button) win
  /// inside their own bounds under SwiftUI's innermost-wins precedence, and
  /// this gesture catches everything else in the row's contentShape.
  private var expandableRowContent: some View {
    rowChrome {
      VStack(alignment: .leading, spacing: PorcelainSpacing.sm) {
        HStack(spacing: PorcelainSpacing.md) {
          Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
              isExpanded.toggle()
            }
          } label: {
            rowCore
          }
          .buttonStyle(.plain)
          .accessibilityLabel(accessibilityLabel)
          .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
          .accessibilityHint(isExpanded ? "Collapse process details" : "Expand process details")

          valueControl

          Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
              isExpanded.toggle()
            }
          } label: {
            Image(systemName: "chevron.right")
              .rotationEffect(.degrees(isExpanded ? 90 : 0))
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(palette.textSecondary)
              .frame(width: 10)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
        }

        indicatorBar
      }
    }
    .onTapGesture {
      withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
        isExpanded.toggle()
      }
    }
  }

  /// Single-process row: no expand button, plain layout, value text still
  /// wrapped so hover-quit works identically to the expandable row.
  private var rowContent: some View {
    rowChrome {
      VStack(alignment: .leading, spacing: PorcelainSpacing.sm) {
        HStack(spacing: PorcelainSpacing.md) {
          rowCore
          valueControl
        }

        indicatorBar
      }
    }
  }

  /// Shared trailing modifier chain for both row variants: idle padding,
  /// the tappable/hoverable region, the glossary tooltip, the value
  /// crossfade animation, and row-level hover detection for the quit
  /// affordance (per spec, the hover region is the whole padded row, not
  /// just the value strip). Identical in both branches so a future
  /// styling change only needs to touch one place.
  private func rowChrome<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
      .padding(.horizontal, PorcelainSpacing.xs)
      .padding(.vertical, PorcelainSpacing.sm)
      .contentShape(Rectangle())
      .help(glossaryEntry?.blurb ?? "")
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: value)
      .onHover { hovering in
        guard store.canTerminate else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
          isRowHovered = hovering
        }
      }
  }

  /// Row value text wrapped in the shared hover-quit affordance. Hidden from
  /// accessibility because the expand button's label (multi-process row) or
  /// the row's combined accessibility label (single-process row) already
  /// states the metric value; without this, VoiceOver would announce the
  /// value a second time as a bare, unlabeled element.
  private var valueControl: some View {
    QuitAffordanceView(
      group: group, store: store,
      accent: palette.accent, secondary: palette.textSecondary,
      isRowHovered: isRowHovered
    ) {
      Text(ValueFormatting.value(metric, for: group))
        .font(.system(size: 15, weight: isTopConsumer ? .semibold : .regular))
        .monospacedDigit()
        .foregroundStyle(isTopConsumer ? palette.textPrimary : palette.textSecondary)
    }
    .accessibilityHidden(true)
  }

  /// Icon + two-line title + spacer, shared by both the expandable and
  /// single-process rows. Excludes the value text and chevron so the
  /// expand button (multi-process case) never wraps the quit affordance.
  private var rowCore: some View {
    HStack(spacing: PorcelainSpacing.md) {
      Image(nsImage: AppIconProvider.icon(for: group))
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 32, height: 32)
        .background(palette.raisedSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .stroke(palette.iconBorder, lineWidth: 1)
        }
        .shadow(color: palette.iconShadowAmbient, radius: 4, y: 2)
        .shadow(color: palette.iconShadowDirect, radius: 1, y: 1)

      VStack(alignment: .leading, spacing: 2) {
        Text(glossaryEntry?.friendlyName ?? group.name)
          .font(.system(size: 15, weight: isTopConsumer ? .semibold : .medium))
          .lineLimit(1)

        Text(subtitle)
          .font(.system(size: 13))
          .foregroundStyle(palette.textSecondary)
          .lineLimit(1)
      }

      Spacer(minLength: PorcelainSpacing.sm)
    }
  }

  private var indicatorBar: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(palette.indicatorTrack)

        Capsule()
          .fill(isTopConsumer ? palette.accent : palette.indicatorFill)
          .frame(width: proxy.size.width * ratio)
      }
    }
    .frame(height: 3)
    .padding(.leading, 48)
  }

  private var accessibilityLabel: String {
    let processWord = group.processCount == 1 ? "process" : "processes"
    let metricLabel = metric == .cpu ? "percent CPU" : "memory"
    let name = glossaryEntry.map { "\($0.friendlyName), \(group.name)" } ?? group.name
    return "\(name), \(group.processCount) \(processWord), "
      + "\(ValueFormatting.value(metric, for: group)) \(metricLabel)"
  }
}

private struct PorcelainChildRowView: View {
  let measurement: ProcessMeasurement
  let metric: MetricKind
  let palette: PorcelainPalette

  private var valueText: String {
    switch metric {
    case .cpu:
      ValueFormatting.percent(measurement.cpuPercent)
    case .memory:
      ValueFormatting.bytes(measurement.snapshot.residentBytes)
    }
  }

  var body: some View {
    HStack(spacing: PorcelainSpacing.sm) {
      Color.clear.frame(width: 42)
      Text(measurement.snapshot.name)
        .font(.system(size: 10.5))
        .foregroundStyle(palette.textSecondary)
        .lineLimit(1)
      Spacer()
      Text(valueText)
        .font(.system(size: 10.5))
        .monospacedDigit()
        .foregroundStyle(palette.textSecondary)
    }
    .padding(.horizontal, PorcelainSpacing.xs)
    .padding(.vertical, PorcelainSpacing.xs)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(measurement.snapshot.name), \(valueText)")
  }
}

private enum PorcelainSpacing {
  static let xs = 4.0
  static let sm = 8.0
  static let md = 16.0
  static let lg = 20.0
}

private struct PorcelainPortRowView: View {
  let group: PortGroup
  let palette: PorcelainPalette
  let store: MonitorStore
  @State private var isRowHovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let maxBadges = 4

  var body: some View {
    HStack(spacing: PorcelainSpacing.sm) {
      Image(nsImage: icon)
        .resizable()
        .frame(width: 18, height: 18)

      Text(group.name)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(palette.textPrimary)
        .lineLimit(1)

      if group.isSystem {
        Text("system")
          .font(.caption2)
          .foregroundStyle(palette.textSecondary)
      }

      Spacer(minLength: PorcelainSpacing.sm)

      if let appGroup = group.appGroup {
        QuitAffordanceView(
          group: appGroup, store: store,
          accent: palette.accent, secondary: palette.textSecondary,
          isRowHovered: isRowHovered
        ) {
          badges
        }
      } else {
        badges
      }
    }
    .padding(.vertical, PorcelainSpacing.xs)
    .frame(height: 44)
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
          .foregroundStyle(palette.textSecondary)
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
    let portsText = group.ports
      .map { "\(String($0.number)) \($0.transport.rawValue.uppercased())" }
      .joined(separator: ", ")
    let origin = group.isSystem ? ", system process" : ""
    return "\(group.name)\(origin), listening on \(portsText)"
  }
}

private struct PorcelainPalette {
  let canvas: Color
  let raisedSurface: Color
  let textPrimary: Color
  let textSecondary: Color
  let borderSubtle: Color
  let accent: Color
  let indicatorTrack: Color
  let indicatorFill: Color
  let iconBorder: Color
  let iconShadowAmbient: Color
  let iconShadowDirect: Color
  let controlTrack: Color
  let controlSelected: Color
  let controlBorder: Color
  let controlShadowAmbient: Color
  let controlShadowDirect: Color

  init(colorScheme: ColorScheme) {
    if colorScheme == .dark {
      canvas = Color(red: 0.09, green: 0.09, blue: 0.095)
      raisedSurface = Color.white.opacity(0.07)
      textPrimary = Color(red: 0.98, green: 0.96, blue: 0.92)
      textSecondary = Color(red: 0.68, green: 0.66, blue: 0.62)
      borderSubtle = Color.white.opacity(0.10)
      accent = Color(red: 0.88, green: 0.55, blue: 0.25)
      indicatorTrack = Color.white.opacity(0.12)
      indicatorFill = Color.white.opacity(0.34)
      iconBorder = Color.white.opacity(0.12)
      iconShadowAmbient = Color.black.opacity(0.18)
      iconShadowDirect = Color.black.opacity(0.14)
      controlTrack = Color.white.opacity(0.05)
      controlSelected = Color.white.opacity(0.11)
      controlBorder = Color.white.opacity(0.12)
      controlShadowAmbient = Color.black.opacity(0.16)
      controlShadowDirect = Color.black.opacity(0.12)
    } else {
      canvas = Color(red: 0.985, green: 0.972, blue: 0.95)
      raisedSurface = Color(red: 0.965, green: 0.945, blue: 0.915)
      textPrimary = Color(red: 0.12, green: 0.125, blue: 0.135)
      textSecondary = Color(red: 0.41, green: 0.42, blue: 0.43)
      borderSubtle = Color.black.opacity(0.08)
      accent = Color(red: 0.85, green: 0.47, blue: 0.085)
      indicatorTrack = Color.black.opacity(0.08)
      indicatorFill = Color.black.opacity(0.28)
      iconBorder = Color.black.opacity(0.10)
      iconShadowAmbient = Color.black.opacity(0.07)
      iconShadowDirect = Color.black.opacity(0.05)
      controlTrack = Color.black.opacity(0.04)
      controlSelected = Color.white.opacity(0.72)
      controlBorder = Color.black.opacity(0.10)
      controlShadowAmbient = Color.black.opacity(0.07)
      controlShadowDirect = Color.black.opacity(0.05)
    }
  }
}
