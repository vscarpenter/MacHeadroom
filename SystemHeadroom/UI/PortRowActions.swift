import Foundation

/// Pure helpers behind the Open and Copy items on a port row. Foundation
/// only, so the menu's decisions stay fixture-testable.
enum PortRowActions {
  /// Rows show up to four badges before the +N chip; the menu mirrors
  /// that cutoff so it never grows past what the row itself shows flat.
  static let flatItemLimit = 4

  /// A browser can open a TCP listener; there is nothing to open on UDP.
  static func url(for port: ListeningPort) -> URL? {
    guard port.transport == .tcp else { return nil }
    return URL(string: "http://\(address(for: port))")
  }

  /// String(port.number), never interpolation of the UInt16 directly:
  /// port numbers must not pick up locale grouping separators.
  static func address(for port: ListeningPort) -> String {
    "localhost:\(String(port.number))"
  }

  static func usesSubmenus(portCount: Int) -> Bool {
    portCount > flatItemLimit
  }

  /// Name-based routing happens on the web ports, so those rows alone
  /// offer the hosts-file names.
  static func isWebPort(_ port: ListeningPort) -> Bool {
    port.transport == .tcp && (port.number == 80 || port.number == 443)
  }

  /// https for 443, http for 80, no port suffix either way; nil for any
  /// other port.
  static func url(for port: ListeningPort, host: String) -> URL? {
    guard port.transport == .tcp else { return nil }
    switch port.number {
    case 443: return URL(string: "https://\(host)")
    case 80: return URL(string: "http://\(host)")
    default: return nil
    }
  }

  /// One alias entry per name, not per port: 443 wins when a row has
  /// both, because that is the URL a person would open.
  static func preferredWebPort(in ports: [ListeningPort]) -> ListeningPort? {
    let web = ports.filter(isWebPort)
    return web.first { $0.number == 443 } ?? web.first
  }
}
