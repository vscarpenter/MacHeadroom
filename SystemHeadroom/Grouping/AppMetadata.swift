/// Plain data the grouping engine needs about a running application. The
/// live NSWorkspace/NSRunningApplication lookup happens above this layer so
/// the engine itself stays pure and fixture-testable.
struct AppMetadata: Sendable, Equatable {
  let pid: Int32
  let bundleIdentifier: String?
  let name: String
}
