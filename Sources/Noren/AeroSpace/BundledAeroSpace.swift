// The AeroSpace inside Noren.app (Contents/Helpers/AeroSpace.app, built by nix/aerospace). It runs
// as a login agent of its own, local.noren.aerospace (Contents/Library/LaunchAgents), which noren
// registers through SMAppService unless [aerospace] start is false: the nix module runs the agent
// itself, under the same label. Being its own agent, AeroSpace keeps running, and the windows stay
// where they are, while noren starts afresh or updates alone.
//
// At start, another AeroSpace running (installed by hand or by Homebrew) is quit, and said so: two
// would fight over every window. Then the agent is registered if it is not, and if the AeroSpace
// running is another build than the one beside noren's `aerospace` command (noren was updated), it
// is restarted onto it.
import AppKit
import NorenCore
import ServiceManagement
import os

final class BundledAeroSpace: Part {
  static let label = "local.noren.aerospace"
  private static let bundleId = "bobko.aerospace"

  private let log = Logger(subsystem: "local.noren", category: "aerospace")
  private let config: AeroSpaceAgentConfig
  /// The bundled app and command
  private let app: URL
  private let command: URL

  /// nil when noren runs without the bundled AeroSpace (`swift run`): then AeroSpace is the user's
  init?(config: AeroSpaceAgentConfig) {
    let contents = Bundle.main.bundleURL.appending(path: "Contents")
    app = contents.appending(path: "Helpers/AeroSpace.app").resolvingSymlinksInPath()
    command = contents.appending(path: "MacOS/aerospace")
    guard FileManager.default.fileExists(atPath: app.path) else { return nil }
    self.config = config
  }

  func start() {
    quitOthers()
    if config.start { register() }
    Task { await restartIfOtherBuild() }
  }

  /// Quits every AeroSpace running that is not the bundled one
  private func quitOthers() {
    for running in NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleId) {
      guard let url = running.bundleURL?.resolvingSymlinksInPath(), url != app else { continue }
      running.terminate()
      Problems.report(
        "quit the AeroSpace at \(url.path): noren runs its own. If it comes back, take it out of "
          + "System Settings > General > Login Items")
    }
  }

  private func register() {
    let service = SMAppService.agent(plistName: "\(Self.label).plist")
    if service.status != .enabled {
      do {
        try service.register()
      } catch {
        log.error("could not register AeroSpace's agent: \(error, privacy: .public)")
      }
    }
    switch service.status {
    case .enabled:
      log.info("AeroSpace runs as \(Self.label, privacy: .public)")
    case .requiresApproval:
      Problems.report(
        "AeroSpace waits to be allowed: turn Noren on in System Settings > General > Login Items")
    default:
      Problems.report("AeroSpace could not be started (its agent is \(service.status))")
    }
  }

  /// Restarts the agent's AeroSpace if it is another build than the bundled one
  private func restartIfOtherBuild() async {
    // Its exit status is not looked at: with no AeroSpace answering, it fails yet names its own
    guard let (_, output) = await Self.run(command.path, ["-v"]),
      let versions = AeroSpaceVersions(output: output), versions.appIsOtherBuild
    else { return }
    log.info(
      "AeroSpace \(versions.app ?? "", privacy: .public) runs; restarting it onto \(versions.command, privacy: .public)"
    )
    let target = "gui/\(getuid())/\(Self.label)"
    let result = await Self.run("/bin/launchctl", ["kickstart", "-k", target])
    if result?.status != 0 {
      Problems.report(
        "could not restart AeroSpace onto noren's build (\(target)): \(result?.output ?? "")")
    }
  }

  /// `executable`'s exit status and output, nil when it could not run. Off the main thread:
  /// AeroSpace may be slow to answer.
  @concurrent
  private nonisolated static func run(_ executable: String, _ arguments: [String]) async -> (
    status: Int32, output: String
  )? {
    let process = Process()
    process.executableURL = URL(filePath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
      try process.run()
    } catch {
      return nil
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
  }
}
