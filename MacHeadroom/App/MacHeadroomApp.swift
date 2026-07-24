import SwiftUI

@main
struct MacHeadroomApp: App {
  @State private var store = MonitorStore()

  var body: some Scene {
    MenuBarExtra {
      PopoverView(store: store)
    } label: {
      menuBarLabel
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(store: store)
    }
  }

  @ViewBuilder
  private var menuBarLabel: some View {
    if store.showsMenuBarText, let cpuPercent = store.systemSummary.cpuPercent {
      Label("\(Int(cpuPercent.rounded()))%", systemImage: "gauge.with.dots.needle.50percent")
        .accessibilityLabel("\(AppIdentity.displayName), \(Int(cpuPercent.rounded())) percent CPU")
    } else {
      Image(systemName: "gauge.with.dots.needle.50percent")
        .accessibilityLabel(AppIdentity.displayName)
    }
  }
}
