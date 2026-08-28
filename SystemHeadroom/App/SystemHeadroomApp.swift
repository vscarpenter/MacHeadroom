import SwiftUI

@main
struct SystemHeadroomApp: App {
  @State private var store = MonitorStore()
  private static let instanceGuard = SingleInstanceGuard()

  init() {
    Self.instanceGuard.activate()
    UpdaterProvider.startBackgroundChecks()
  }

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
      Label {
        Text("\(Int(cpuPercent.rounded()))%")
      } icon: {
        Image("MenuBarGlyph")
      }
      .accessibilityLabel("\(AppIdentity.displayName), \(Int(cpuPercent.rounded())) percent CPU")
      .help(AppIdentity.displayName)
    } else {
      Image("MenuBarGlyph")
        .accessibilityLabel(AppIdentity.displayName)
        .help(AppIdentity.displayName)
    }
  }
}
