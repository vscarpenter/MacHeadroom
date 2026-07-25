import AppKit
import SwiftUI

/// The About tab: identity, version, credit, and links. Rudimentary by
/// design; acknowledgements and release notes can slot in beneath the
/// links later without touching the General tab.
struct AboutView: View {
  var body: some View {
    VStack(spacing: 8) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 64, height: 64)

      Text(AppIdentity.displayName)
        .font(.title3.weight(.semibold))

      Text(AppIdentity.versionDescription)
        .font(.caption)
        .foregroundStyle(.secondary)

      VStack(spacing: 4) {
        HStack(spacing: 4) {
          Text("Created by")
          Link("Vinny Carpenter", destination: URL(string: "https://vinny.dev/")!)
        }
        Link("macheadroom.com", destination: URL(string: "https://macheadroom.com")!)
      }
      .padding(.top, 8)
    }
    .padding(24)
    .frame(width: 360)
  }
}

#if DEBUG
  #Preview {
    AboutView()
  }
#endif
