// While the bar is away from over the menu bar, watches for the moment to bring it back: the
// pointer has left the top of the screens and no menu is open. Both are followed by events,
// not looked at on a timer:
//
//   pointer  mouse-moved and dragged events, through a global monitor (over other apps' windows,
//            the menu bar among them) and a local one (over noren's own)
//   menus    HIToolbox's distributed notifications com.apple.HIToolbox.beginMenuTrackingNotification
//            and endMenuTrackingNotification, which a menu opening and closing in any app posts.
//            They are taken as they come, though noren is never the active app: AppKit holds
//            distributed notifications back from an inactive app unless the observer asks for
//            them at once.
import AppKit

final class MenuBarWatch: NSObject {
  private static let beginMenuTracking = Notification.Name(
    "com.apple.HIToolbox.beginMenuTrackingNotification")
  private static let endMenuTracking = Notification.Name(
    "com.apple.HIToolbox.endMenuTrackingNotification")
  private static let pointerEvents: NSEvent.EventTypeMask = [
    .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
  ]

  /// Whether a point, in screen coordinates, is in the menu bar of some screen.
  private let inMenuBar: (NSPoint) -> Bool
  private let cover: () -> Void
  private var monitors: [Any] = []
  private var menuOpen = false

  /// Calls `cover` once the pointer is out of the menu bar, as `inMenuBar` tells, and no menu is
  /// open, each time a watch is started.
  init(inMenuBar: @escaping (NSPoint) -> Bool, cover: @escaping () -> Void) {
    self.inMenuBar = inMenuBar
    self.cover = cover
  }

  /// Starts watching; covers at once if the pointer is already away.
  func start() {
    guard monitors.isEmpty else { return }
    menuOpen = false
    let center = DistributedNotificationCenter.default()
    center.addObserver(
      self, selector: #selector(menuBegan), name: Self.beginMenuTracking, object: nil,
      suspensionBehavior: .deliverImmediately)
    center.addObserver(
      self, selector: #selector(menuEnded), name: Self.endMenuTracking, object: nil,
      suspensionBehavior: .deliverImmediately)
    if let global = NSEvent.addGlobalMonitorForEvents(
      matching: Self.pointerEvents,
      handler: { [unowned self] _ in MainActor.assumeIsolated { check() } })
    {
      monitors.append(global)
    }
    if let local = NSEvent.addLocalMonitorForEvents(
      matching: Self.pointerEvents,
      handler: { [unowned self] event in
        check()
        return event
      })
    {
      monitors.append(local)
    }
    check()
  }

  func stop() {
    for monitor in monitors { NSEvent.removeMonitor(monitor) }
    monitors = []
    DistributedNotificationCenter.default().removeObserver(self)
  }

  @objc private func menuBegan(_ notification: Notification) {
    menuOpen = true
  }

  @objc private func menuEnded(_ notification: Notification) {
    menuOpen = false
    check()
  }

  private func check() {
    guard !monitors.isEmpty, !menuOpen, !inMenuBar(NSEvent.mouseLocation) else { return }
    stop()
    cover()
  }
}
