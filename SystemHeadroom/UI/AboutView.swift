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

      Text("Build: \(TerminationCapability.current.buildFlavorName)")
        .font(.caption)
        .foregroundStyle(.secondary)

      VStack(spacing: 4) {
        HStack(spacing: 4) {
          Text("Created by")
          Link("Vinny Carpenter", destination: URL(string: "https://vinny.dev/")!)
        }
        HStack(spacing: 12) {
          Link("Website", destination: AppIdentity.websiteURL)
          Link("Privacy Policy", destination: AppIdentity.privacyPolicyURL)
        }
      }
      .padding(.top, 8)
    }
    .padding(24)
    .frame(width: 440)
  }
}

#if DEBUG
  #Preview {
    AboutView()
  }
#endif
