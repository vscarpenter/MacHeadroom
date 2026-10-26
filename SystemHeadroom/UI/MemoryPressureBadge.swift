import SwiftUI

/// Memory pressure and swap, shared by both popover headers. A filled
/// dot in the system semantic color, the level word, then the swap
/// figure. Renders in every state (Unknown and "Swap —" included) so the
/// header's height never depends on what the sysctl returned.
///
/// The text helpers are nonisolated: `View` is main-actor isolated, and
/// the pure formatting must stay callable from a test on any thread.
struct MemoryPressureBadge: View {
  let level: MemoryPressureLevel?
  let swapUsedBytes: UInt64?
  var secondaryColor: Color = .secondary

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(Self.color(for: level))
        .frame(width: 8, height: 8)
      Text(Self.levelText(level))
      Text(Self.swapText(swapUsedBytes))
        .foregroundStyle(secondaryColor)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Self.accessibilityLabel(level: level, swapUsedBytes: swapUsedBytes))
  }

  nonisolated static func levelText(_ level: MemoryPressureLevel?) -> String {
    level?.displayName ?? "Unknown"
  }

  nonisolated static func swapText(_ swapUsedBytes: UInt64?) -> String {
    guard let swapUsedBytes else { return "Swap —" }
    return "Swap \(ValueFormatting.bytes(swapUsedBytes))"
  }

  nonisolated static func accessibilityLabel(level: MemoryPressureLevel?, swapUsedBytes: UInt64?) -> String {
    let state = levelText(level).lowercased()
    let swap = swapUsedBytes.map { "\(ValueFormatting.bytes($0)) of swap in use" } ?? "swap unknown"
    return "Memory pressure \(state), \(swap)"
  }

  nonisolated static func color(for level: MemoryPressureLevel?) -> Color {
    switch level {
    case .normal: .green
    case .warning: .orange
    case .critical: .red
    case nil: .gray
    }
  }
}
