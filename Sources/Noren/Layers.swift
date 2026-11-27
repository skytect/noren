// Floating windows stay above tiled ones (WindowLayers): after each AeroSpace event the windows are
// listed again, compared with the levels the window server has them at, and the Dock payload
// (Dock/payload.m) puts the newly tiled ones under the other windows and brings back the ones
// floated, made fullscreen or minimized. Without the payload in the Dock, or with one from before
// noren knew to ask (the Dock loads a new one only when it restarts), nothing changes: only the
// Dock may change another app's window level (docs/dock.md).
import CoreGraphics
import NorenCore
import os

final class Layers: Part {
  private let log = Logger(subsystem: "local.noren", category: "layers")
  private let aeroSpace: AeroSpaceClient
  /// Has the border look at its window again: its ring goes where its window went
  private let wakeBorder: () -> Void
  /// The latest look; each waits for the one before
  private var looking: Task<Void, Never>?

  init(aeroSpace: AeroSpaceClient, wakeBorder: @escaping () -> Void) {
    self.aeroSpace = aeroSpace
    self.wakeBorder = wakeBorder
  }

  func handle(_ event: AeroSpaceEvent) {
    if case .modeChanged = event { return }
    looking = Task { [previous = looking] in
      await previous?.value
      await look()
    }
  }

  private func look() async {
    guard let skyLight = SkyLight.shared else { return }
    let windows: [ListedWindow]
    do {
      windows = try await aeroSpace.run(
        ["list-windows", "--all", "--json", "--format", ListedWindow.format],
        as: [ListedWindow].self)
    } catch {
      log.error("could not list the windows: \(error, privacy: .public)")
      return
    }
    let current = Set(windows.compactMap(\.nativeId).filter(skyLight.isBelow))
    let layers = WindowLayers(from: current, to: windows)
    guard !layers.isEmpty else { return }
    _ = await DockPayload.send(.below, layers.below)
    _ = await DockPayload.send(.normal, layers.normal)
    wakeBorder()
  }
}
