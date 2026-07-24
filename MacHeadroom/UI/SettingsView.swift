import SwiftUI

struct SettingsView: View {
  @Bindable var store: MonitorStore

  private let intervalOptions: [TimeInterval] = [2, 5, 10, 30]

  var body: some View {
    Form {
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
    .padding(20)
    .frame(width: 360)
  }
}

#Preview {
  SettingsView(store: PreviewFixtures.makeStore())
}
