import AppKit
import NorenCore
import os

/// noren running: its config read, its parts started, and AeroSpace's events handed to them.
///
/// A change to the config file that reads well starts noren afresh (the same process, exec'd
/// again), so no part needs a way to stop; one that does not read well is reported, and noren
/// carries on as it was until the file is fixed.
final class NorenApp {
  private let log = Logger(subsystem: "local.noren", category: "app")
  private let aeroSpace = AeroSpaceClient()
  private var parts: [any Part] = []
  private var watcher: ConfigWatcher?
  /// The config file's text noren runs with, nil for no file
  private var configText: String?

  func run() -> Never {
    NSApplication.shared.setActivationPolicy(.accessory)
    do {
      configText = try ConfigFile.text()
      start(try ConfigFile.config(configText))
    } catch {
      Problems.report("\(ConfigFile.url.path): \(error)")
    }
    do {
      watcher = try ConfigWatcher { [unowned self] in configChanged() }
    } catch {
      Problems.report("noren cannot follow changes to its config: \(error)")
    }
    NSApplication.shared.run()
    exit(0)
  }

  private func start(_ config: Config) {
    parts = makeParts(config: config, aeroSpace: aeroSpace)
    for part in parts { part.start() }
    log.info("started \(self.parts.count) parts")
    Task {
      for await event in aeroSpace.events() {
        for part in parts { part.handle(event) }
      }
    }
  }

  private func configChanged() {
    let text: String?
    do {
      text = try ConfigFile.text()
    } catch {
      Problems.report("\(ConfigFile.url.path): \(error)")
      return
    }
    guard text != configText else { return }
    do {
      _ = try ConfigFile.config(text)
    } catch {
      Problems.report("\(ConfigFile.url.path): \(error); noren keeps running as it was")
      configText = text
      return
    }
    log.info("the config changed; starting afresh")
    guard let executable = Bundle.main.executablePath else { return }
    execv(executable, CommandLine.unsafeArgv)
    Problems.report(
      "noren could not start afresh with its new config: \(String(cString: strerror(errno)))")
  }
}
