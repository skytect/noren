// The pointer following keyboard focus; PointerFollower (NorenCore) decides where it goes.
import NorenCore
import os

final class Pointer: Part {
  private let log = Logger(subsystem: "local.noren", category: "pointer")
  private let aeroSpace: AeroSpaceClient
  private var follower = PointerFollower()
  /// The latest move; each waits for the one before, so the pointer ends where focus did
  private var following: Task<Void, Never>?

  init(aeroSpace: AeroSpaceClient) {
    self.aeroSpace = aeroSpace
  }

  /// Leaves the pointer where it is for the switch to `workspace` about to be made, as one picked
  /// with the pointer.
  func stay(forSwitchTo workspace: String) {
    follower.stay(forSwitchTo: workspace)
  }

  func handle(_ event: AeroSpaceEvent) {
    guard let target = follower.follow(event) else { return }
    following = Task { [previous = following] in
      await previous?.value
      do {
        _ = try await aeroSpace.run(["move-mouse", target.rawValue])
      } catch {
        // As on a workspace without windows, where there is nothing to move to
        log.debug("move-mouse \(target.rawValue, privacy: .public): \(error, privacy: .public)")
      }
    }
  }
}
