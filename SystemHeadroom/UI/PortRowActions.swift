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
}
