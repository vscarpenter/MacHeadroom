import SwiftUI

@main
struct MacHeadroomApp: App {
  @State private var store = MonitorStore()

  var body: some Scene {
    MenuBarExtra(AppIdentity.displayName, systemImage: "gauge.with.dots.needle.50percent") {
      PopoverView(store: store)
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView()
    }
  }
}
