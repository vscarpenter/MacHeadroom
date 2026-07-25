import SwiftUI

struct SettingsView: View {
  @Bindable var store: MonitorStore

  private let intervalOptions: [TimeInterval] = [2, 5, 10, 30]

  var body: some View {
    TabView {
      general
        .tabItem { Label("General", systemImage: "gearshape") }
      AboutView()
        .tabItem { Label("About", systemImage: "info.circle") }
    }
    .frame(width: 440)
  }

  private var general: some View {
    Form {
      Section("Monitoring") {
        Picker("Sampling interval", selection: $store.samplingInterval) {
          ForEach(intervalOptions, id: \.self) { interval in
            Text("\(Int(interval))s").tag(interval)
          }
        }

        Toggle("Launch at login", isOn: $store.launchAtLogin)

        Toggle("Show CPU percent in the menu bar", isOn: $store.showsMenuBarText)

        Toggle(
          "Use Activity Monitor's per-core convention",
          isOn: Binding(
            get: { store.cpuConvention == .perCore },
            set: { store.cpuConvention = $0 ? .perCore : .machineCapacity }
          )
        )
      }

      Section("Appearance") {
        Toggle("Turn on Max Headroom mode", isOn: $store.maxHeadroomModeEnabled)
          .help("Use the Porcelain Native broadcast appearance in the menu bar popover.")

        Text("Adds the porcelain interface, amber signal details, and synthetic host cameo.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(20)
  }
}

#if DEBUG
  #Preview {
    SettingsView(store: PreviewFixtures.makeStore())
  }
#endif
