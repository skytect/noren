// Focus rules: commands run as focus moves into and out of matching windows (Config's
// focus-rule). For example, a remote desktop's session windows can put AeroSpace in a mode that
// passes every key through, and the keyboard remapper in a layer without its own shortcuts.
//
// When noren starts or AeroSpace comes back, what was run before is unknown, so every rule runs
// its commands for where focus is: enter inside it, leave outside. Leave commands are written to
// be harmless when nothing was entered.
import Foundation
import NorenCore
import os

final class FocusRules: Part {
  private let log = Logger(subsystem: "local.noren", category: "focus-rules")
  private let aeroSpace: AeroSpaceClient
  private var tracker: FocusRuleTracker
  /// The latest focus change being followed; each waits for the one before, so commands run in
  /// the order focus moved
  private var following: Task<Void, Never>?

  init(rules: [FocusRule], aeroSpace: AeroSpaceClient) {
    self.aeroSpace = aeroSpace
    tracker = FocusRuleTracker(rules: rules)
  }

  func handle(_ event: AeroSpaceEvent) {
    switch event {
    case .connected: follow(reset: true)
    case .focusChanged: follow(reset: false)
    default: break
    }
  }

  private func follow(reset: Bool) {
    following = Task { [previous = following] in
      await previous?.value
      let window: FocusedWindow?
      do {
        window = try await focusedWindow()
      } catch {
        log.error("could not read the focused window: \(error, privacy: .public)")
        return
      }
      for command in reset ? tracker.reset(window) : tracker.focus(window) {
        await run(command)
      }
    }
  }

  private func focusedWindow() async throws -> FocusedWindow? {
    do {
      let windows = try await aeroSpace.run(
        ["list-windows", "--focused", "--json", "--format", ListedWindow.format],
        as: [ListedWindow].self)
      return windows.first.map { FocusedWindow(appId: $0.bundleId, title: $0.title) }
    } catch AeroSpaceError.noWindowFocused {
      return nil
    }
  }

  /// Runs `command`: through AeroSpace's socket when it is an aerospace command, else as a
  /// program, looked up on PATH unless it is a path.
  private func run(_ command: [String]) async {
    let shown = command.joined(separator: " ")
    if command[0] == "aerospace" {
      do {
        _ = try await aeroSpace.run(Array(command.dropFirst()))
      } catch {
        log.error("\(shown, privacy: .public): \(error, privacy: .public)")
      }
      return
    }
    let process = Process()
    if command[0].contains("/") {
      process.executableURL = URL(fileURLWithPath: command[0])
      process.arguments = Array(command.dropFirst())
    } else {
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = command
    }
    process.standardInput = FileHandle.nullDevice
    let status: Int32 = await withCheckedContinuation { continuation in
      process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
      do {
        try process.run()
      } catch {
        process.terminationHandler = nil
        log.error("\(shown, privacy: .public): \(error, privacy: .public)")
        continuation.resume(returning: -1)
      }
    }
    if status > 0 { log.error("\(shown, privacy: .public) exited with \(status)") }
  }
}
