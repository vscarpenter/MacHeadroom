import Foundation

/// The loopback names in /etc/hosts: what a reverse proxy on 80 or 443
/// routes by. The parse is pure so a fixture test pins it; the read is
/// measured inside the sandboxed test host.
enum HostsFile {
  private static let stockNames: Set<String> = [
    "localhost", "localhost.localdomain", "broadcasthost",
  ]
  private static let loopbackAddresses: Set<String> = ["127.0.0.1", "::1"]

  /// Names on 127.0.0.1 or ::1 lines, minus the stock entries, sorted and
  /// de-duplicated. Comments and blocklist lines (0.0.0.0) are ignored.
  static func loopbackNames(in contents: String) -> [String] {
    var names: Set<String> = []
    for rawLine in contents.split(whereSeparator: \.isNewline) {
      let line = rawLine.split(separator: "#", maxSplits: 1).first ?? ""
      let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
      guard fields.count >= 2, loopbackAddresses.contains(fields[0]) else { continue }
      for name in fields.dropFirst() where !stockNames.contains(name) {
        names.insert(name)
      }
    }
    return names.sorted()
  }

  /// nil when the file cannot be read, so the menu shows localhost only.
  static func readLoopbackNames(path: String = "/etc/hosts") -> [String]? {
    guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    return loopbackNames(in: contents)
  }
}
