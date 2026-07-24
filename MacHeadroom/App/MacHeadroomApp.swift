import Foundation

@main
enum MacHeadroomApp {
  @MainActor
  static func main() async {
    guard CommandLine.arguments.contains("--phase-zero-probe") else {
      FileHandle.standardError.write(
        Data(
          "\(AppIdentity.displayName) Phase 0 build. Run with --phase-zero-probe.\n"
            .utf8
        )
      )
      return
    }

    let report = await SandboxProbe.run()

    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(report)
      FileHandle.standardOutput.write(data)
      FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
      FileHandle.standardError.write(
        Data("Unable to encode the Phase 0 report: \(error)\n".utf8)
      )
    }
  }
}
