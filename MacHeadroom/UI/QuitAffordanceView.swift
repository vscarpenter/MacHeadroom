import SwiftUI

/// Hover-revealed quit control shared by both skins. Renders the row's
/// value text; hover crossfades it to an ✕; a first click arms an inline
/// "Quit?" confirm; a second click quits. Hover exit or four seconds
/// disarms. The value keeps its frame (opacity swap, never removal), so
/// row height and width cannot shift.
struct QuitAffordanceView<Value: View>: View {
  let group: AppGroup
  let store: MonitorStore
  let accent: Color
  let secondary: Color
  @ViewBuilder let value: () -> Value

  @State private var isHovering = false
  @State private var isConfirming = false
  @State private var disarmTask: Task<Void, Never>?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var showsControls: Bool {
    store.canTerminate && (isHovering || isConfirming)
  }

  var body: some View {
    ZStack(alignment: .trailing) {
      value().opacity(showsControls ? 0 : 1)
      if showsControls {
        controls
      }
    }
    .onHover { hovering in
      guard store.canTerminate else { return }
      withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
        isHovering = hovering
        if !hovering { disarm() }
      }
    }
  }

  @ViewBuilder
  private var controls: some View {
    if isConfirming {
      Button {
        disarm()
        store.quit(group)
      } label: {
        Text("Quit?")
          .font(.callout.weight(.semibold))
          .foregroundStyle(accent)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Confirm quit \(group.name)")
    } else {
      Button {
        isConfirming = true
        disarmTask = Task {
          try? await Task.sleep(for: .seconds(4))
          if !Task.isCancelled { isConfirming = false }
        }
      } label: {
        Image(systemName: "xmark.circle")
          .foregroundStyle(secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Quit \(group.name)")
    }
  }

  private func disarm() {
    disarmTask?.cancel()
    disarmTask = nil
    isConfirming = false
  }
}

extension View {
  /// Row-level quit context menu and VoiceOver actions. Applied only
  /// when the store can terminate, so the sandboxed build's hierarchy
  /// is untouched.
  @ViewBuilder
  func quitContextMenu(for group: AppGroup, store: MonitorStore) -> some View {
    if store.canTerminate {
      self
        .contextMenu {
          Button("Quit \(group.name)") { store.quit(group) }
          Button("Force Quit \(group.name)", role: .destructive) {
            store.forceQuit(group)
          }
        }
        .accessibilityAction(named: "Quit") { store.quit(group) }
        .accessibilityAction(named: "Force Quit") { store.forceQuit(group) }
    } else {
      self
    }
  }
}
