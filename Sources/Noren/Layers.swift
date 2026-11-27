// Floating windows stay above tiled ones (WindowLayers): after each AeroSpace event the windows are
// listed again, and the Dock payload (Dock/payload.m) puts the newly tiled ones below the normal
// level and brings back the ones floated, made fullscreen or minimized. Without the payload in the
// Dock nothing changes: only the Dock may change another app's window level (docs/dock.md).
//
// What is below is forgotten when AeroSpace comes back and whenever the payload cannot be reached,
// so every window is set again on the next look.
import CoreGraphics
import NorenCore
import os

final class Layers: Part {
  private let log = Logger(subsystem: "local.noren", category: "layers")
  private let aeroSpace: AeroSpaceClient
  /// Has the border look at its window again: its ring goes where its window went
  private let wakeBorder: () -> Void
  /// The windows below, nil when unknown
  private var applied: Set<CGWindowID>?
  /// The latest look; each waits for the one before
  private var looking: Task<Void, Never>?

  init(aeroSpace: AeroSpaceClient, wakeBorder: @escaping () -> Void) {
    self.aeroSpace = aeroSpace
    self.wakeBorder = wakeBorder
  }

  func handle(_ event: AeroSpaceEvent) {
    switch event {
    case .connected:
      applied = nil
      look()
    case .modeChanged: break
    default: look()
    }
  }

  /// Whether `window` is below the normal level
  func isBelow(_ window: CGWindowID) -> Bool {
    applied?.contains(window) ?? false
  }

  private func look() {
    looking = Task { [previous = looking] in
      await previous?.value
      await apply()
    }
  }

  private func apply() async {
    let windows: [ListedWindow]
    do {
      windows = try await aeroSpace.run(
        ["list-windows", "--all", "--json", "--format", ListedWindow.format],
        as: [ListedWindow].self)
    } catch {
      log.error("could not list the windows: \(error, privacy: .public)")
      return
    }
    let layers = WindowLayers(from: applied, to: windows)
    guard !layers.isEmpty else { return }
    guard await DockPayload.send(.below, layers.below),
      await DockPayload.send(.normal, layers.normal)
    else {
      applied = nil
      return
    }
    applied = layers.applied
    wakeBorder()
  }
}
