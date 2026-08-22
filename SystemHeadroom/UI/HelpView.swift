import SwiftUI
import AppKit
import Observation

enum HelpDestination: Hashable {
  case directEdition
}

/// A brief, task-oriented guide for the menu-bar app. The process-control
/// section deliberately follows the running build's capability so the App
/// Store edition never promises a control it cannot offer.
struct HelpView: View {
  let store: MonitorStore
  let directEditionClaimURL: URL?
  let requestedSection: HelpDestination?
  @State private var directClaim = DirectEditionClaimModel()

  init(
    store: MonitorStore,
    directEditionClaimURL: URL? = AppIdentity.directEditionClaimURL,
    requestedSection: HelpDestination? = nil
  ) {
    self.store = store
    self.directEditionClaimURL = directEditionClaimURL
    self.requestedSection = requestedSection
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Using System Headroom")
            .font(.title2.weight(.semibold))

          Text("A quick way to see what is using your Mac right now.")
            .foregroundStyle(.secondary)
        }

        if requestedSection == .directEdition {
          directEditionTransfer
        }

        HelpSection("Start here", systemImage: "menubar.rectangle") {
          HelpStep(
            number: 1,
            title: "Open the menu-bar popover",
            detail: "Select the System Headroom icon in the menu bar. The app takes a fresh sample each time you open it."
          )
          HelpStep(
            number: 2,
            title: "Choose CPU, Memory, or Ports",
            detail: "Use the picker at the top to change what you are investigating."
          )
          HelpStep(
            number: 3,
            title: "Start with the first row",
            detail: "The list is ordered by impact, so the first app is the best place to look when your Mac feels busy."
          )
        }

        HelpSection("Read the signal", systemImage: "gauge.with.dots.needle.67percent") {
          HelpFact(
            title: "Headroom",
            detail: "The large percentage is what remains available. More headroom means more room for your Mac to respond."
          )
          HelpFact(
            title: "CPU and Memory",
            detail: memoryDetail
          )
          HelpFact(
            title: "Ports",
            detail: "This shows local processes that are listening for network connections. It does not show every connection your Mac makes."
          )
        }

        HelpSection("Keep it current", systemImage: "arrow.clockwise") {
          HelpFact(
            title: "Refresh now",
            detail: "Use the refresh button at the bottom of the popover when you want a new sample immediately."
          )
          HelpFact(
            title: "Adjust the cadence",
            detail: "In General, choose a sampling interval, show CPU in the menu bar, or launch System Headroom when you sign in."
          )
        }

        processControls

        if requestedSection != .directEdition {
          directEditionTransfer
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: 440, height: 510)
    .accessibilityIdentifier("system-headroom-help")
  }

  private var memoryDetail: String {
    switch store.processMemoryMetric {
    case .physicalFootprint:
      "Each row groups an app with its related helper processes. Memory uses physical footprint, matching Activity Monitor's Memory column."
    case .residentSize:
      "Each row groups an app with its related helper processes. Memory values marked RSS use resident size because the App Store sandbox blocks Activity Monitor's physical-footprint metric; GPU-heavy apps can differ substantially."
    }
  }

  @ViewBuilder
  private var directEditionTransfer: some View {
    if DirectEditionAccessPresentation.isVisible(
      canTerminate: store.canTerminate,
      claimEndpoint: directEditionClaimURL
    ), let endpoint = directEditionClaimURL {
      HelpSection("Direct edition", systemImage: "arrow.right.circle") {
        HelpFact(
          title: "Why there are two editions",
          detail: "The App Store edition runs in Apple's sandbox. It provides monitoring and App Store updates, but it cannot read Activity Monitor's physical-footprint memory or quit other apps."
        )
        HelpFact(
          title: "What Direct adds",
          detail: "System Headroom Direct is Developer ID signed and Apple notarized. It uses physical-footprint memory, adds Quit and Force Quit, installs alongside this edition, and keeps itself up to date with built-in update checks."
        )
        HelpFact(
          title: "Included with your purchase",
          detail: "There is no additional payment or account. Verification sends only your App Store purchase evidence—never process samples, computer names, or preferences."
        )

        HelpStep(
          number: 1,
          title: "Verify your purchase",
          detail: "System Headroom sends only your App Store purchase evidence to the transfer service."
        )
        HelpStep(
          number: 2,
          title: "Open the download page",
          detail: "Your browser opens macheadroom.com with a private link to the notarized installer."
        )
        HelpStep(
          number: 3,
          title: "Install Direct",
          detail: "Open the downloaded disk image and drag System Headroom Direct into Applications."
        )

        switch directClaim.state {
        case .ready:
          Button("Verify purchase and continue") {
            directClaim.claim(using: endpoint)
          }
          .help("Verify this App Store purchase, then continue on macheadroom.com.")
        case .verifying:
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text("Verifying your App Store purchase…")
              .foregroundStyle(.secondary)
          }
        case .readyToOpen(let claimURL):
          Button("Open download page") {
            NSWorkspace.shared.open(claimURL)
          }
          Text("Verify again anytime to download the newest version.")
            .font(.caption)
            .foregroundStyle(.secondary)
        case .failed(let message):
          Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
          Button("Try again") {
            directClaim.claim(using: endpoint)
          }
        }
      }
      .id(HelpDestination.directEdition)
      .accessibilityIdentifier("direct-edition-help-section")
    }
  }

  @ViewBuilder
  private var processControls: some View {
    if store.canTerminate {
      HelpSection("Process controls", systemImage: "xmark.circle") {
        HelpFact(
          title: "Quit an app group",
          detail: "Move the pointer over a CPU or Memory row, select the ×, then select Quit? within four seconds to confirm."
        )
        HelpFact(
          title: "Force Quit only when needed",
          detail: "Control-click a row to choose Quit or Force Quit. These actions apply to the whole app group, not an individual helper process."
        )
      }
    } else {
      HelpSection("Process controls", systemImage: "lock") {
        HelpFact(
          title: "This edition monitors only",
          detail: "The App Store edition can show resource use and listening ports, but macOS sandboxing prevents it from quitting or force quitting other processes."
        )
        Text("Build: \(TerminationCapability.current.buildFlavorName)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.top, 2)
      }
    }
  }
}

@MainActor
@Observable
private final class DirectEditionClaimModel {
  enum State: Equatable {
    case ready
    case verifying
    case readyToOpen(URL)
    case failed(String)
  }

  private(set) var state: State = .ready

  func claim(using endpoint: URL) {
    guard state != .verifying else { return }
    state = .verifying

    Task {
      do {
        let claimURL = try await DirectEditionClaimClient(endpoint: endpoint).claim()
        state = .readyToOpen(claimURL)
      } catch let error as DirectEditionClaimError {
        state = .failed(error.localizedDescription)
      } catch {
        state = .failed("The transfer service is unavailable. Try again later.")
      }
    }
  }
}

private struct HelpSection<Content: View>: View {
  let title: String
  let systemImage: String
  @ViewBuilder let content: Content

  init(
    _ title: String,
    systemImage: String,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.systemImage = systemImage
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: systemImage)
        .font(.headline)

      VStack(alignment: .leading, spacing: 12) {
        content
      }
      .padding(.leading, 24)
    }
  }
}

private struct HelpStep: View {
  let number: Int
  let title: String
  let detail: String

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Text(number.formatted())
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .frame(width: 18, height: 18)
        .background(.quaternary, in: Circle())
        .accessibilityHidden(true)

      HelpFact(title: title, detail: detail)
    }
  }
}

private struct HelpFact: View {
  let title: String
  let detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.subheadline.weight(.medium))
      Text(detail)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

#if DEBUG
  #Preview("Help — App Store") {
    HelpView(store: PreviewFixtures.makeStore())
  }
#endif
