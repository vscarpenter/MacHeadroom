import AppKit
import SwiftUI

/// What a port row's Open and Copy items do. Injected so a test can
/// record calls; `.live` hands the URL to the default browser and the
/// address to the general pasteboard.
@MainActor
struct PortActionHandler {
  let open: (URL) -> Void
  let copy: (String) -> Void

  static let live = PortActionHandler(
    open: { NSWorkspace.shared.open($0) },
    copy: { address in
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(address, forType: .string)
    })
}

extension View {
  /// The one context menu both port row skins attach: quit items when
  /// the build can terminate and the row has an app group, then an Open
  /// item per TCP port and a Copy item per port. VoiceOver gets the same
  /// items as custom actions.
  func portRowMenu(
    for group: PortGroup, store: MonitorStore, handler: PortActionHandler
  ) -> some View {
    self
      .contextMenu {
        PortRowMenuItems(group: group, store: store, handler: handler, flattened: false)
      }
      .accessibilityActions {
        PortRowMenuItems(group: group, store: store, handler: handler, flattened: true)
      }
  }
}

private struct PortRowMenuItems: View {
  let group: PortGroup
  let store: MonitorStore
  let handler: PortActionHandler
  /// Custom accessibility actions are a flat list of buttons: no
  /// dividers, no submenus.
  let flattened: Bool

  private var openablePorts: [ListeningPort] {
    group.ports.filter { PortRowActions.url(for: $0) != nil }
  }

  var body: some View {
    if store.canTerminate, let appGroup = group.appGroup {
      QuitMenuItems(group: appGroup, store: store)
      if !flattened {
        Divider()
      }
    }
    if !flattened, PortRowActions.usesSubmenus(portCount: group.ports.count) {
      if !openablePorts.isEmpty {
        Menu("Open in Browser") { openButtons }
      }
      Menu("Copy Address") { copyButtons }
    } else {
      openButtons
      copyButtons
    }
    if let webPort = PortRowActions.preferredWebPort(in: group.ports),
      !store.localHostnames.isEmpty
    {
      if flattened {
        aliasOpenButtons(for: webPort)
        aliasCopyButtons(for: webPort)
      } else {
        Menu("Open as") { aliasOpenButtons(for: webPort) }
        Menu("Copy as") { aliasCopyButtons(for: webPort) }
      }
    }
  }

  private var openButtons: some View {
    ForEach(openablePorts, id: \.self) { port in
      Button("Open \(PortRowActions.address(for: port))") {
        if let url = PortRowActions.url(for: port) {
          handler.open(url)
        }
      }
    }
  }

  private var copyButtons: some View {
    ForEach(group.ports, id: \.self) { port in
      Button("Copy \(PortRowActions.address(for: port))") {
        handler.copy(PortRowActions.address(for: port))
      }
    }
  }

  private func aliasURLs(for port: ListeningPort) -> [URL] {
    store.localHostnames.compactMap { PortRowActions.url(for: port, host: $0) }
  }

  private func aliasOpenButtons(for port: ListeningPort) -> some View {
    ForEach(aliasURLs(for: port), id: \.self) { url in
      Button("Open \(url.absoluteString)") { handler.open(url) }
    }
  }

  private func aliasCopyButtons(for port: ListeningPort) -> some View {
    ForEach(aliasURLs(for: port), id: \.self) { url in
      Button("Copy \(url.absoluteString)") { handler.copy(url.absoluteString) }
    }
  }
}

/// The visible way into a port row's menu: a borderless ellipsis after
/// the badges. A plain click opens the same items Control-click does, so
/// the actions are discoverable without knowing the gesture. Hidden from
/// VoiceOver because the row already exposes the items as custom actions.
struct PortRowMenuButton: View {
  let group: PortGroup
  let store: MonitorStore
  var handler: PortActionHandler = .live
  var tint: Color = .secondary

  var body: some View {
    Menu {
      PortRowMenuItems(group: group, store: store, handler: handler, flattened: false)
    } label: {
      Image(systemName: "ellipsis.circle")
        .foregroundStyle(tint)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .accessibilityHidden(true)
  }
}
