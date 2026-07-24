/// Friendly names and one-line explanations for macOS daemons that show up
/// in the top-10 lists without any app identity. Curated and offline, per
/// the brief: no network, no third-party data. Only groups with no bundle
/// identifier are eligible — real apps already carry their own names.
enum ProcessGlossary {
  struct Entry: Equatable {
    let friendlyName: String
    let blurb: String
  }

  static func entry(for group: AppGroup) -> Entry? {
    guard group.bundleIdentifier == nil else { return nil }
    return entriesByTruncatedName[truncated(group.name)]
  }

  /// kinfo_proc.p_comm caps process names at MAXCOMLEN (16 characters), so
  /// the sampler sees "searchpartyuseragent" as "searchpartyusera". Keys
  /// are stored and looked up in that truncated form.
  private static func truncated(_ name: String) -> String {
    String(name.prefix(16))
  }

  private static let entriesByTruncatedName: [String: Entry] = {
    var table: [String: Entry] = [:]
    for (name, friendly, blurb) in catalog {
      table[truncated(name)] = Entry(friendlyName: friendly, blurb: blurb)
    }
    return table
  }()

  /// User-session daemons and agents only: App Sandbox hides root and
  /// other-user processes, so system-level daemons never reach the list.
  /// Blurbs are one calm, honest sentence about function.
  private static let catalog: [(String, String, String)] = [
    ("biomesyncd", "Device Activity Sync",
     "Syncs the on-device activity history that powers Siri suggestions across your devices."),
    ("BiomeAgent", "Device Activity Collector",
     "Records app activity events macOS uses for Siri and smart suggestions."),
    ("corespotlightd", "Spotlight Indexing",
     "Maintains the search index Spotlight uses for content inside apps."),
    ("mds", "Spotlight Index Server",
     "Coordinates building the Spotlight search index."),
    ("mds_stores", "Spotlight Index Storage",
     "Stores and updates Spotlight's index files."),
    ("mdworker", "Spotlight Worker",
     "Reads file contents to add them to the Spotlight index."),
    ("mdworker_shared", "Spotlight Worker",
     "Reads file contents to add them to the Spotlight index."),
    ("suggestd", "Siri Suggestions",
     "Finds names, events, and suggestions in Mail, Messages, and Safari content."),
    ("sirittsd", "Siri Voice",
     "Generates Siri's spoken voice from text."),
    ("mediaanalysisd", "Photo & Video Analysis",
     "Scans photos and videos for faces, scenes, and text so search works."),
    ("photoanalysisd", "Photos Library Analysis",
     "Analyzes the Photos library for people, scenes, and memories."),
    ("photolibraryd", "Photos Library",
     "Manages the Photos library database and its syncing."),
    ("replayd", "Screen Recording",
     "Handles screen recording and screen broadcasts."),
    ("trustd", "Certificate Verification",
     "Checks the security certificates apps and websites present."),
    ("cloudd", "iCloud Sync",
     "Moves app data to and from iCloud."),
    ("bird", "iCloud Drive",
     "Syncs files with iCloud Drive."),
    ("nsurlsessiond", "Background Transfers",
     "Runs downloads and uploads apps schedule for the background."),
    ("cfprefsd", "Preferences Service",
     "Reads and writes app settings files."),
    ("distnoted", "Notification Relay",
     "Passes internal notifications between apps and system services."),
    ("WindowManager", "Window Management",
     "Runs Stage Manager and window tiling."),
    ("universalaccessd", "Accessibility",
     "Powers accessibility features like VoiceOver and Zoom."),
    ("tccd", "Privacy Permissions",
     "Enforces which apps may use the camera, microphone, files, and more."),
    ("lsd", "App Registry",
     "Keeps the catalog of installed apps and which app opens which file."),
    ("secd", "Keychain",
     "Serves passwords and keys from your Keychain."),
    ("imagent", "iMessage & FaceTime",
     "Keeps you signed in to iMessage and FaceTime."),
    ("identityservicesd", "Apple ID Services",
     "Manages the encrypted identities behind iMessage, FaceTime, and Handoff."),
    ("akd", "Apple ID Sign-In",
     "Handles Apple ID authentication."),
    ("passd", "Wallet & Apple Pay",
     "Manages Wallet passes and Apple Pay."),
    ("searchpartyuseragent", "Find My",
     "Participates in the Find My network to help locate devices."),
    ("sharingd", "AirDrop & Handoff",
     "Runs AirDrop, Handoff, and nearby sharing."),
    ("rapportd", "Device Link",
     "Maintains the local connections Apple devices use to work together."),
    ("dataaccessd", "Accounts Sync",
     "Syncs Mail, Contacts, and Calendar accounts in the background."),
    ("CalendarAgent", "Calendar Sync",
     "Fetches and updates calendar events in the background."),
    ("contactsd", "Contacts",
     "Maintains and syncs your contacts database."),
    ("appstoreagent", "App Store",
     "Handles App Store downloads and updates."),
    ("commerce", "App Store Purchases",
     "Processes App Store purchases and receipts."),
    ("AMPLibraryAgent", "Music & TV Library",
     "Manages the Music and TV app libraries."),
    ("ScreenTimeAgent", "Screen Time",
     "Tracks app usage for Screen Time."),
    ("coreduetd", "Usage Patterns",
     "Learns device usage patterns so background work runs at good times."),
    ("knowledgeconstructiond", "On-Device Learning",
     "Builds the on-device knowledge used for personalized suggestions."),
    ("pboard", "Clipboard",
     "Runs the system clipboard."),
    ("loginwindow", "Login Session",
     "Manages your login session and the login window."),
    ("SystemUIServer", "Menu Bar Services",
     "Hosts some of the menu bar's system items."),
    ("deleted", "Storage Cleanup",
     "Frees space by removing caches and purgeable data."),
    ("QuickLookUIService", "Quick Look Preview",
     "Renders file previews for Quick Look."),
  ]
}
