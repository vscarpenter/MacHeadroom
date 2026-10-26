import SwiftUI

struct SettingsView: View {
  @Bindable var store: MonitorStore
  let directEditionClaimURL: URL?

  private let intervalOptions: [TimeInterval] = [2, 5, 10, 30]
  private let thresholdOptions = [50, 75, 90]
  private let sustainOptions = [30, 60, 120, 300]
  @State private var selectedTab: SettingsTab = .general
  @State private var requestedHelpSection: HelpDestination?

  init(
    store: MonitorStore,
    directEditionClaimURL: URL? = AppIdentity.directEditionClaimURL
  ) {
    self.store = store
    self.directEditionClaimURL = directEditionClaimURL
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      general
        .tabItem { Label("General", systemImage: "gearshape") }
        .tag(SettingsTab.general)
      HelpView(
        store: store,
        directEditionClaimURL: directEditionClaimURL,
        requestedSection: requestedHelpSection
      )
        .tabItem { Label("Help", systemImage: "questionmark.circle") }
        .tag(SettingsTab.help)
      AboutView()
        .tabItem { Label("About", systemImage: "info.circle") }
        .tag(SettingsTab.about)
    }
    .frame(width: 440)
    .onChange(of: selectedTab) { _, newTab in
      if newTab != .help {
        requestedHelpSection = nil
      }
    }
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

      Section("Alerts") {
        Toggle("Notify me about sustained CPU use", isOn: $store.cpuAlertsEnabled)

        Picker("Above", selection: $store.cpuAlertThresholdPercent) {
          ForEach(thresholdOptions, id: \.self) { percent in
            Text("\(percent)%").tag(percent)
          }
        }
        .disabled(!store.cpuAlertsEnabled)

        Picker("For at least", selection: $store.cpuAlertSustainSeconds) {
          ForEach(sustainOptions, id: \.self) { seconds in
            Text(CPUAlertPolicy.describe(sustainSeconds: seconds)).tag(seconds)
          }
        }
        .disabled(!store.cpuAlertsEnabled)

        Text(
          "Percent of one core, the way Activity Monitor counts. Alerts keep sampling running while the popover is closed, like the menu bar percent does."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Appearance") {
        Picker("Popover appearance", selection: $store.usesPorcelainAppearance) {
          Text("Porcelain Native").tag(true)
          Text("Classic compact").tag(false)
        }
        .help("Choose the visual style used by the menu bar popover.")

        Text("Porcelain Native is the default, with warmer surfaces and a clearer headroom view.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if DirectEditionAccessPresentation.isVisible(
        canTerminate: store.canTerminate,
        claimEndpoint: directEditionClaimURL
      ) {
        Section("Edition") {
          LabeledContent("Current build", value: TerminationCapability.current.buildFlavorName)

          Button("Compare editions…") {
            requestedHelpSection = .directEdition
            selectedTab = .help
          }
          .help("Open Help to compare the App Store and Direct editions.")
          .accessibilityIdentifier("compare-direct-edition-button")
        }
        .accessibilityIdentifier("direct-edition-settings-section")
      }
    }
    .padding(20)
  }
}

private enum SettingsTab: Hashable {
  case general
  case help
  case about
}

#if DEBUG
  #Preview {
    SettingsView(store: PreviewFixtures.makeStore())
  }
#endif
