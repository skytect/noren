// New windows nest like a dwindle layout (DwindleNesting says where). The Dock payload keeps each
// new window hidden meanwhile (Appear); it is shown once nested or left, faded in, or at once when
// it floats.
//
// One new window at a time: windows that open together (an app restoring several) each see the
// layout the one before left.
//
// AeroSpace's floating rules must have taken their windows first, or a window about to float
// would be joined. AeroSpace broadcasts window-detected before it runs those rules
// (onWindowDetected in Sources/AppBundle/tree/MacWindow.swift), but the broadcast is a task queued
// on AeroSpace's main actor, and the rules float a window there without yielding it (an app-id
// match and `layout floating` never wait), so the event goes out and the list-windows below is
// answered only after they ran. A rule that matches on the window title would wait for the title
// and break this.
//
// The join cannot be one of those rules itself, which would place the window in one move: an
// on-window-detected `if` tests one window's, workspace's, app's or monitor's variables, and none
// of them counts the workspace's windows. So it costs two aerospace calls, list-windows and
// join-with; join-with answers only once AeroSpace has set the windows' new frames (runLightSession
// in Sources/AppBundle/layout/refresh.swift).
import CoreGraphics
import NorenCore
import os

final class Dwindle: Part {
  private let log = Logger(subsystem: "local.noren", category: "dwindle")
  private let aeroSpace: AeroSpaceClient
  /// Has the payload show a new window (a window server id), faded in or at once
  private let show: (CGWindowID, Bool) -> Void
  /// The latest new window being nested; each waits for the one before
  private var following: Task<Void, Never>?
  /// The window server ids of the app windows there when AeroSpace last connected
  private var existing: Set<CGWindowID> = []

  init(aeroSpace: AeroSpaceClient, show: @escaping (CGWindowID, Bool) -> Void) {
    self.aeroSpace = aeroSpace
    self.show = show
  }

  func handle(_ event: AeroSpaceEvent) {
    if case .connected = event { existing = Self.appWindows() }
    guard case .windowDetected(let window, _, _, _) = event else { return }
    following = Task { [previous = following] in
      await previous?.value
      await nest(window)
    }
  }

  /// Joins the new window `window` (an AeroSpace window id) with the one it opened next to, when
  /// that nests it, then has the payload show it.
  private func nest(_ window: UInt32) async {
    let windows: [ListedWindow]
    do {
      windows = try await aeroSpace.run(
        ["list-windows", "--all", "--json", "--format", ListedWindow.format],
        as: [ListedWindow].self)
    } catch {
      log.error("could not list the windows: \(error, privacy: .public)")
      return
    }
    switch DwindleNesting(of: window, among: windows, existing: existing) {
    case .join(let nativeId, let direction):
      do {
        _ = try await aeroSpace.run(
          ["join-with", "--window-id", String(window), direction.rawValue])
      } catch {
        log.error("could not nest window \(window): \(error, privacy: .public)")
      }
      show(nativeId, true)
    case .leave(let nativeId, let fade):
      show(nativeId, fade)
    case .gone:
      break
    }
  }

  /// The window server ids of every app window, on screen or not
  private static func appWindows() -> Set<CGWindowID> {
    let infos = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
    return Set(
      infos.compactMap { info in
        info[kCGWindowLayer as String] as? Int == 0
          ? info[kCGWindowNumber as String] as? CGWindowID : nil
      })
  }
}
