// Staying on a workspace whose last window closed; StayHistory (NorenCore) has the why and the
// decision.
import NorenCore
import os

final class Stay: Part {
  private let log = Logger(subsystem: "local.noren", category: "stay")
  private let aeroSpace: AeroSpaceClient
  /// The close bindings the config names; nil to read AeroSpace's
  private let closeBindings: [String]?
  private var history: StayHistory
  /// The latest event being followed; each waits for the one before, so the looks are in order
  private var following: Task<Void, Never>?

  init(config: StayConfig, aeroSpace: AeroSpaceClient) {
    self.aeroSpace = aeroSpace
    closeBindings = config.closeBindings
    history = StayHistory(closeBindings: Set(config.closeBindings ?? []))
  }

  func handle(_ event: AeroSpaceEvent) {
    let received = ContinuousClock.now
    following = Task { [previous = following] in
      await previous?.value
      await follow(event, received: received)
    }
  }

  private func follow(_ event: AeroSpaceEvent, received: ContinuousClock.Instant) async {
    var change: StayHistory.Change?
    switch event {
    case .bindingTriggered(_, let binding):
      history.bindingTriggered(binding, at: received)
      return
    case .connected:
      if closeBindings == nil { await readCloseBindings() }
      history.forget()
    case .focusedWorkspaceChanged(let workspace, let previous):
      change = StayHistory.Change(workspace: workspace, previous: previous)
    default:
      break
    }
    let occupied: Set<String>?
    do {
      occupied = Set(try await aeroSpace.workspaceNames(["--monitor", "all", "--empty", "no"]))
    } catch {
      log.error("could not read the occupied workspaces: \(error, privacy: .public)")
      occupied = nil
    }
    guard
      let back = history.follow(
        change, received: received, occupied: occupied, lookedAt: ContinuousClock.now),
      let change
    else { return }
    log.info(
      """
      workspace \(back, privacy: .public) lost its last window and focus went to \
      \(change.workspace, privacy: .public): back to \(back, privacy: .public)
      """)
    do {
      _ = try await aeroSpace.run(["workspace", back])
    } catch {
      log.error(
        "could not go back to workspace \(back, privacy: .public): \(error, privacy: .public)")
    }
  }

  /// Takes the close bindings from AeroSpace's config, which may have changed while AeroSpace was
  /// away.
  private func readCloseBindings() async {
    do {
      history.closeBindings = try await aeroSpace.configFacts().closeBindings
    } catch {
      Problems.report("stay could not read AeroSpace's close bindings: \(error)")
    }
  }
}
