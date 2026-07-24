import Testing

@testable import MacHeadroom

@Suite("Process glossary")
struct ProcessGlossaryTests {
  private func group(name: String, bundleIdentifier: String? = nil) -> AppGroup {
    AppGroup(
      groupKey: bundleIdentifier ?? "name:\(name)",
      name: name,
      bundleIdentifier: bundleIdentifier,
      representativePID: 100,
      cpuPercent: 1,
      memoryBytes: 1000,
      children: []
    )
  }

  @Test("A known daemon maps to a friendly name and explanation")
  func knownDaemonMaps() throws {
    let entry = try #require(ProcessGlossary.entry(for: group(name: "corespotlightd")))
    #expect(entry.friendlyName == "Spotlight Indexing")
    #expect(!entry.blurb.isEmpty)
  }

  @Test("An unknown process name has no glossary entry")
  func unknownNameHasNoEntry() {
    #expect(ProcessGlossary.entry(for: group(name: "com.example.mystery")) == nil)
  }

  @Test("A canonical name longer than 16 characters matches its truncated form")
  func longNameMatchesTruncation() throws {
    // The kernel caps kinfo_proc.p_comm at MAXCOMLEN (16), so the sampler
    // reports "searchpartyuseragent" as "searchpartyusera".
    let entry = try #require(ProcessGlossary.entry(for: group(name: "searchpartyusera")))
    #expect(entry.friendlyName == "Find My")
  }

  @Test("A group with real app metadata never gets a glossary entry")
  func appGroupsAreExempt() {
    let finder = group(name: "trustd", bundleIdentifier: "com.apple.finder")
    #expect(ProcessGlossary.entry(for: finder) == nil)
  }
}
