import SwiftUI

@main
struct MacHeadroomApp: App {
  var body: some Scene {
    MenuBarExtra(AppIdentity.displayName, systemImage: "gauge.with.dots.needle.50percent") {
      PlaceholderPopoverView()
    }
    .menuBarExtraStyle(.window)
  }
}

private struct PlaceholderPopoverView: View {
  var body: some View {
    Text(AppIdentity.displayName)
      .font(.headline)
      .padding()
      .frame(width: 340)
  }
}
