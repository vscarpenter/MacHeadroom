import AppKit
import SwiftUI

struct MaxHeadroomPopoverView: View {
  let store: MonitorStore
  @State private var selectedMetric: MetricKind = .cpu
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme

  private var palette: PorcelainPalette {
    PorcelainPalette(colorScheme: colorScheme)
  }

  private var groups: [AppGroup] {
    selectedMetric == .cpu ? store.topCPUGroups : store.topMemoryGroups
  }

  private var maxValue: Double {
    groups.first.flatMap { selectedMetric.value(of: $0) } ?? 0
  }

  private var headroomPercent: Int? {
    switch selectedMetric {
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
    }
  }

  private var headroomText: String {
    headroomPercent.map(String.init) ?? "—"
  }

  private var usageDetail: String {
    switch selectedMetric {
    case .cpu:
      let cpu = ValueFormatting.percent(store.systemSummary.cpuPercent)
      return "\(cpu) in use · "
        + "\(ValueFormatting.bytes(store.systemSummary.memoryUsedBytes)) of "
        + ValueFormatting.bytes(store.systemSummary.memoryTotalBytes)
    case .memory:
      return "\(ValueFormatting.bytes(store.systemSummary.memoryUsedBytes)) in use · "
        + "\(ValueFormatting.bytes(store.systemSummary.memoryTotalBytes)) total"
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
    .tint(palette.accent)
  }

  private var header: some View {
    VStack(spacing: PorcelainSpacing.sm) {
      HStack(alignment: .top, spacing: PorcelainSpacing.md) {
        VStack(alignment: .leading, spacing: PorcelainSpacing.xs) {
          BroadcastCeilingTicks(accent: palette.accent)
            .frame(width: 76, height: 4)

          Text("\(selectedMetric.rawValue) headroom")
            .font(.system(size: 17, weight: .medium))

          HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(headroomText)
              .font(.system(size: 42, weight: .regular, design: .rounded))
              .monospacedDigit()
              .contentTransition(.numericText())

            if headroomPercent != nil {
              Text("%")
                .font(.system(size: 23, weight: .regular, design: .rounded))
            }
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel(
            headroomPercent.map { "\($0) percent \(selectedMetric.rawValue) headroom" }
              ?? "\(selectedMetric.rawValue) headroom unavailable"
          )

          Text(usageDetail)
            .font(.system(size: 11))
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
        }

        Spacer(minLength: 0)

        VStack(alignment: .trailing, spacing: 2) {
          Text("CH \(headroomText)")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1.3)
            .foregroundStyle(palette.textSecondary)

          BroadcastHostMark(palette: palette)
            .frame(width: 82, height: 58)
            .accessibilityHidden(true)
        }
      }

      HStack {
        Spacer()
        Picker("Metric", selection: $selectedMetric) {
          ForEach(MetricKind.allCases) { metric in
            Text(metric.rawValue).tag(metric)
          }
        }
        .pickerStyle(.segmented)
        .frame(width: 174)
        .labelsHidden()
        .accessibilityLabel("Metric")
      }
    }
    .padding(PorcelainSpacing.md)
    .background {
      PorcelainScanlines(color: palette.textPrimary)
        .opacity(colorScheme == .dark ? 0.045 : 0.025)
        .accessibilityHidden(true)
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selectedMetric)
  }

  private var list: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        if groups.isEmpty {
          VStack(spacing: PorcelainSpacing.sm) {
            Image(systemName: "waveform.path")
              .font(.title3)
            Text("Waiting for a signal…")
              .font(.system(size: 13, weight: .medium))
            Text("The first sample will appear in a moment.")
              .font(.caption)
              .foregroundStyle(palette.textSecondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 52)
        } else {
          ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
            MaxHeadroomGroupRowView(
              group: group,
              metric: selectedMetric,
              maxValue: maxValue,
              isTopConsumer: index == 0,
              palette: palette
            )

            if group.id != groups.last?.id {
              Rectangle()
                .fill(palette.borderSubtle)
                .frame(height: 1)
                .padding(.leading, 48)
            }
          }
        }
      }
      .padding(.horizontal, PorcelainSpacing.md)
      .padding(.vertical, PorcelainSpacing.xs)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: groups)
    }
    // MenuBarExtra(.window) fixes its size at presentation time. Keep this
    // independent of list contents so the first live sample cannot collapse it.
    .frame(height: 330)
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
          Label("Quit Mac Headroom", systemImage: "power")
        }
      } label: {
        Image(systemName: "ellipsis.circle")
          .frame(width: 24, height: 24)
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .help("More")
      .accessibilityLabel("More options")
    }
    .padding(.horizontal, PorcelainSpacing.md)
    .padding(.vertical, PorcelainSpacing.sm)
  }

  private var porcelainDivider: some View {
    Rectangle()
      .fill(palette.borderSubtle)
      .frame(height: 1)
  }
}

private struct MaxHeadroomGroupRowView: View {
  let group: AppGroup
  let metric: MetricKind
  let maxValue: Double
  let isTopConsumer: Bool
  let palette: PorcelainPalette
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isExpanded = false

  private var value: Double? { metric.value(of: group) }

  private var ratio: Double {
    guard let value, maxValue > 0 else { return 0 }
    return min(max(value / maxValue, 0), 1)
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
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: PorcelainSpacing.sm) {
          expandControl

          Image(nsImage: AppIconProvider.icon(for: group))
            .resizable()
            .frame(width: 24, height: 24)
            .background(palette.raisedSurface, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
              RoundedRectangle(cornerRadius: 6)
                .stroke(palette.borderSubtle, lineWidth: 1)
            }

          VStack(alignment: .leading, spacing: 1) {
            Text(glossaryEntry?.friendlyName ?? group.name)
              .font(.system(size: 13, weight: isTopConsumer ? .semibold : .medium))
              .lineLimit(1)

            Text(subtitle)
              .font(.system(size: 10.5))
              .foregroundStyle(palette.textSecondary)
              .lineLimit(1)
          }

          Spacer(minLength: PorcelainSpacing.sm)

          Text(ValueFormatting.value(metric, for: group))
            .font(.system(size: 13, weight: isTopConsumer ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(isTopConsumer ? palette.textPrimary : palette.textSecondary)
        }

        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Capsule()
              .fill(palette.indicatorTrack)

            Capsule()
              .fill(isTopConsumer ? palette.accent : palette.indicatorFill)
              .frame(width: proxy.size.width * ratio)

            Capsule()
              .fill(palette.accent)
              .frame(width: 3)
          }
        }
        .frame(height: 2)
        .padding(.leading, 40)
      }
      .padding(.horizontal, PorcelainSpacing.xs)
      .padding(.vertical, 7)
      .background(
        isTopConsumer ? palette.topConsumerSurface : Color.clear,
        in: RoundedRectangle(cornerRadius: 10)
      )
      .overlay {
        if isTopConsumer {
          RoundedRectangle(cornerRadius: 10)
            .stroke(palette.accentBorder, lineWidth: 1)
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(accessibilityLabel)
      .help(glossaryEntry?.blurb ?? "")
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: value)

      if isExpanded {
        ForEach(group.children, id: \.snapshot.pid) { child in
          MaxHeadroomChildRowView(
            measurement: child,
            metric: metric,
            palette: palette
          )
        }
      }
    }
  }

  @ViewBuilder
  private var expandControl: some View {
    if group.processCount > 1 {
      Button {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
          isExpanded.toggle()
        }
      } label: {
        Image(systemName: "chevron.right")
          .rotationEffect(.degrees(isExpanded ? 90 : 0))
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(palette.textSecondary)
          .frame(width: 10, height: 24)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
    } else {
      Color.clear
        .frame(width: 10, height: 24)
        .accessibilityHidden(true)
    }
  }

  private var accessibilityLabel: String {
    let processWord = group.processCount == 1 ? "process" : "processes"
    let metricLabel = metric == .cpu ? "percent CPU" : "memory"
    let name = glossaryEntry.map { "\($0.friendlyName), \(group.name)" } ?? group.name
    return "\(name), \(group.processCount) \(processWord), "
      + "\(ValueFormatting.value(metric, for: group)) \(metricLabel)"
  }
}

private struct MaxHeadroomChildRowView: View {
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

private struct BroadcastCeilingTicks: View {
  let accent: Color

  var body: some View {
    HStack(spacing: 8) {
      ForEach([10.0, 18.0, 14.0, 22.0], id: \.self) { width in
        Capsule()
          .fill(accent)
          .frame(width: width, height: 2)
      }
    }
    .accessibilityHidden(true)
  }
}

private struct PorcelainScanlines: View {
  let color: Color

  var body: some View {
    Canvas { context, size in
      var y = 1.0
      while y < size.height {
        var line = Path()
        line.move(to: CGPoint(x: 0, y: y))
        line.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(line, with: .color(color), lineWidth: 0.5)
        y += 4
      }
    }
  }
}

private struct BroadcastHostMark: View {
  let palette: PorcelainPalette

  var body: some View {
    Canvas { context, size in
      let ink = palette.textPrimary.opacity(0.74)
      let faint = palette.textPrimary.opacity(0.10)
      let accent = palette.accent.opacity(0.75)

      var scanY = 2.0
      while scanY < size.height {
        var scanline = Path()
        scanline.move(to: CGPoint(x: 2, y: scanY))
        scanline.addLine(to: CGPoint(x: size.width - 2, y: scanY))
        context.stroke(scanline, with: .color(faint), lineWidth: 0.5)
        scanY += 5
      }

      let faceRect = CGRect(
        x: size.width * 0.35,
        y: size.height * 0.15,
        width: size.width * 0.34,
        height: size.height * 0.52
      )
      context.stroke(
        Path(roundedRect: faceRect, cornerRadius: size.width * 0.08),
        with: .color(ink),
        lineWidth: 1.2
      )

      var shoulders = Path()
      shoulders.move(to: CGPoint(x: size.width * 0.15, y: size.height * 0.96))
      shoulders.addCurve(
        to: CGPoint(x: size.width * 0.85, y: size.height * 0.96),
        control1: CGPoint(x: size.width * 0.25, y: size.height * 0.68),
        control2: CGPoint(x: size.width * 0.75, y: size.height * 0.68)
      )
      context.stroke(shoulders, with: .color(ink), lineWidth: 1.2)

      for index in 0..<5 {
        var hair = Path()
        let offset = Double(index) * size.width * 0.045
        hair.move(
          to: CGPoint(
            x: size.width * 0.35 + offset,
            y: size.height * 0.18
          )
        )
        hair.addCurve(
          to: CGPoint(
            x: size.width * 0.58 + offset * 0.35,
            y: size.height * 0.04
          ),
          control1: CGPoint(
            x: size.width * 0.38 + offset,
            y: size.height * 0.08
          ),
          control2: CGPoint(
            x: size.width * 0.52 + offset * 0.5,
            y: size.height * 0.03
          )
        )
        context.stroke(hair, with: .color(index == 0 ? accent : ink), lineWidth: 1)
      }

      let glassesY = size.height * 0.34
      let lensWidth = size.width * 0.17
      let lensHeight = size.height * 0.16
      let leftLens = CGRect(
        x: size.width * 0.31,
        y: glassesY,
        width: lensWidth,
        height: lensHeight
      )
      let rightLens = CGRect(
        x: size.width * 0.55,
        y: glassesY,
        width: lensWidth,
        height: lensHeight
      )

      for lens in [leftLens, rightLens] {
        context.stroke(
          Path(roundedRect: lens, cornerRadius: 2),
          with: .color(ink),
          lineWidth: 1.2
        )
        for stripe in 1...3 {
          var shutter = Path()
          let y = lens.minY + CGFloat(stripe) * lens.height / 4
          shutter.move(to: CGPoint(x: lens.minX + 2, y: y))
          shutter.addLine(to: CGPoint(x: lens.maxX - 2, y: y))
          context.stroke(shutter, with: .color(accent), lineWidth: 0.8)
        }
      }

      var bridge = Path()
      bridge.move(to: CGPoint(x: leftLens.maxX, y: glassesY + lensHeight * 0.45))
      bridge.addLine(to: CGPoint(x: rightLens.minX, y: glassesY + lensHeight * 0.45))
      context.stroke(bridge, with: .color(ink), lineWidth: 1.2)

      var nose = Path()
      nose.move(to: CGPoint(x: size.width * 0.515, y: size.height * 0.43))
      nose.addLine(to: CGPoint(x: size.width * 0.49, y: size.height * 0.58))
      nose.addLine(to: CGPoint(x: size.width * 0.54, y: size.height * 0.58))
      context.stroke(nose, with: .color(ink), lineWidth: 0.9)

      var mouth = Path()
      mouth.move(to: CGPoint(x: size.width * 0.44, y: size.height * 0.65))
      mouth.addCurve(
        to: CGPoint(x: size.width * 0.60, y: size.height * 0.65),
        control1: CGPoint(x: size.width * 0.49, y: size.height * 0.69),
        control2: CGPoint(x: size.width * 0.55, y: size.height * 0.69)
      )
      context.stroke(mouth, with: .color(ink), lineWidth: 0.9)
    }
  }
}

private enum PorcelainSpacing {
  static let xs = 4.0
  static let sm = 8.0
  static let md = 16.0
}

private struct PorcelainPalette {
  let canvas: Color
  let raisedSurface: Color
  let topConsumerSurface: Color
  let textPrimary: Color
  let textSecondary: Color
  let borderSubtle: Color
  let accent: Color
  let accentBorder: Color
  let indicatorTrack: Color
  let indicatorFill: Color

  init(colorScheme: ColorScheme) {
    if colorScheme == .dark {
      canvas = Color(red: 0.09, green: 0.09, blue: 0.095)
      raisedSurface = Color.white.opacity(0.07)
      topConsumerSurface = Color.white.opacity(0.055)
      textPrimary = Color(red: 0.98, green: 0.96, blue: 0.92)
      textSecondary = Color(red: 0.68, green: 0.66, blue: 0.62)
      borderSubtle = Color.white.opacity(0.10)
      accent = Color(red: 0.88, green: 0.55, blue: 0.25)
      accentBorder = Color(red: 0.48, green: 0.32, blue: 0.19).opacity(0.8)
      indicatorTrack = Color.white.opacity(0.12)
      indicatorFill = Color.white.opacity(0.34)
    } else {
      canvas = Color(red: 0.985, green: 0.972, blue: 0.95)
      raisedSurface = Color(red: 0.965, green: 0.945, blue: 0.915)
      topConsumerSurface = Color(red: 0.99, green: 0.955, blue: 0.905)
      textPrimary = Color(red: 0.12, green: 0.125, blue: 0.135)
      textSecondary = Color(red: 0.41, green: 0.42, blue: 0.43)
      borderSubtle = Color.black.opacity(0.08)
      accent = Color(red: 0.85, green: 0.47, blue: 0.085)
      accentBorder = Color(red: 0.90, green: 0.70, blue: 0.46).opacity(0.58)
      indicatorTrack = Color.black.opacity(0.08)
      indicatorFill = Color.black.opacity(0.28)
    }
  }
}
