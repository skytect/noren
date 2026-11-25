// The workspace strip. A three-finger horizontal swipe on a trackpad drags a strip of the focused
// screen's workspaces along with the fingers and, on lift-off, switches to the one it was dragged
// to (SwipeGesture in NorenCore has the gesture, StripWorkspaces which workspaces are in it). Any
// other workspace change, such as a key or a click in the bar, flashes the same strip, but not
// focus merely moving to another screen.
//
// macOS's own three-finger swipe between Spaces and full-screen apps should be off, or both
// follow the same swipe.
import AppKit
import IOKit.hid
import NorenCore
import os

final class Strip: Part {
  private static let holdAfterSwipe = Duration.milliseconds(450)
  private static let holdAfterFlash = Duration.milliseconds(800)

  private let log = Logger(subsystem: "local.noren", category: "strip")
  private let aeroSpace: AeroSpaceClient
  private let panel = StripPanel()
  private var gesture = SwipeGesture()
  private var prefetch = SwipeGesture.Prefetch.unavailable
  /// Counts the touches the strip was asked for, so an answer for an older one is dropped
  private var prefetchGeneration = 0
  private var trackpads: Trackpads?
  /// The latest AeroSpace call; each waits for the one before, so they run in order, as the
  /// prefetch for a touch before the switch it ends in
  private var following: Task<Void, Never>?

  init(aeroSpace: AeroSpaceClient) {
    self.aeroSpace = aeroSpace
  }

  func start() {
    if !IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) {
      Problems.report(
        "noren has no Input Monitoring permission: swipes are off until it is granted and noren"
          + " restarts")
    }
    do {
      trackpads = try Trackpads(
        frames: { [unowned self] frame in follow(frame) },
        attached: { [unowned self] in gesture.reset() })
    } catch {
      Problems.report("swipes between workspaces are off: \(error)")
    }
  }

  func handle(_ event: AeroSpaceEvent) {
    guard case .focusedWorkspaceChanged(_, let left) = event else { return }
    following = Task { [previous = following] in
      await previous?.value
      // Focus moving to another screen changes the focused workspace too, but the one left is
      // still on screen
      do {
        let visible = try await aeroSpace.workspaceNames(["--monitor", "all", "--visible"])
        if visible.contains(left) { return }
      } catch {
        log.error("could not read the visible workspaces: \(error, privacy: .public)")
      }
      flash(await workspaces(withSpare: false))
    }
  }

  private func follow(_ frame: TouchFrame) {
    for step in gesture.follow(frame, prefetch: prefetch) {
      switch step {
      case .armed:
        prefetchGeneration += 1
        let generation = prefetchGeneration
        prefetch = .pending
        following = Task { [previous = following] in
          await previous?.value
          let strip = await workspaces(withSpare: true)
          guard generation == prefetchGeneration else { return }
          prefetch = strip.map { .ready($0) } ?? .unavailable
        }
      case .began(let strip):
        guard let screen = screen(strip) else { continue }
        panel.layOut(strip.names, on: screen)
        panel.place(Double(strip.focused), animated: false)
        panel.show()
      case .moved(let position):
        panel.place(position, animated: false)
      case .ended(let target, let workspace):
        panel.place(Double(target), animated: true)
        panel.hide(after: Self.holdAfterSwipe)
        if let workspace {
          following = Task { [previous = following] in
            await previous?.value
            do {
              _ = try await aeroSpace.run(["workspace", workspace])
            } catch {
              log.error(
                "could not switch to workspace \(workspace, privacy: .public): \(error, privacy: .public)"
              )
            }
          }
        }
      }
    }
  }

  private func flash(_ strip: StripWorkspaces?) {
    guard let strip, !gesture.isTracking, let screen = screen(strip) else { return }
    let name = strip.names[strip.focused]
    // While the strip is up on this screen, slide within it, so it does not change shape under
    // the selection (a workspace just left empty stays in it until it fades)
    if panel.isShown, panel.isLaidOut(on: screen), let index = panel.names.firstIndex(of: name) {
      panel.place(Double(index), animated: true)
    } else {
      panel.layOut(strip.names, on: screen)
      panel.place(Double(strip.focused), animated: false)
    }
    panel.show()
    panel.hide(after: Self.holdAfterFlash)
  }

  /// The screen `strip` is on, or the main screen when that one is gone.
  private func screen(_ strip: StripWorkspaces) -> NSScreen? {
    NSScreen.aeroSpaceMonitor(strip.monitorId) ?? NSScreen.main
  }

  /// The focused screen's strip, nil when AeroSpace does not answer.
  private func workspaces(withSpare: Bool) async -> StripWorkspaces? {
    do {
      let listed = try await aeroSpace.run(
        ["list-workspaces", "--monitor", "focused", "--json", "--format", ListedWorkspace.format],
        as: [ListedWorkspace].self)
      let used = try await aeroSpace.workspaceNames(["--monitor", "focused", "--empty", "no"])
      return StripWorkspaces(listed: listed, used: Set(used), withSpare: withSpare)
    } catch {
      log.error("could not read the workspaces: \(error, privacy: .public)")
      return nil
    }
  }
}
