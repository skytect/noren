// Accessibility's notifications about one window, so the border moves when the window does
// instead of polling for it: the window moved, resized, minimized or closed, or its app hidden or
// shown again.
//
// The window is found among its app's Accessibility windows by its window server id, read with
// the private _AXUIElementGetWindow (looked up at run time), the call AeroSpace itself uses to give
// windows their %{window-id-native}. So every window AeroSpace can focus has an element to watch.
//
// Finding the window and registering for its notifications are calls into the window's app, which
// block for as long as the app takes to answer (up to Accessibility's 6 seconds when it hangs).
// They run off the main thread; the notifications arrive on the main run loop.
import AppKit
import os

final class WindowWatch {
  private let onChange: () -> Void
  private var observer: AXObserver?
  private var stopped = false

  /// Starts watching `window`, of the app with process id `pid`; `onChange` runs on the main
  /// thread for each notification.
  init(window: CGWindowID, pid: pid_t, onChange: @escaping () -> Void) {
    self.onChange = onChange
    if Self.getWindow == nil, !Self.reportedMissing {
      Self.reportedMissing = true
      Problems.report(
        "_AXUIElementGetWindow is missing; the border follows windows only on AeroSpace's events")
    }
    let watch = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
    Task {
      guard let observer = await Self.observe(window, pid: pid, watch: watch), !stopped else {
        return
      }
      self.observer = observer
      CFRunLoopAddSource(
        CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
  }

  /// Stops the notifications; none arrives after this.
  func stop() {
    stopped = true
    guard let observer else { return }
    CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    self.observer = nil
  }

  private typealias GetWindow =
    @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) ->
    AXError

  private static var reportedMissing = false

  /// _AXUIElementGetWindow, or nil when it is missing, which is reported.
  private nonisolated static let getWindow: GetWindow? = {
    guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow")
    else { return nil }
    return unsafeBitCast(address, to: GetWindow.self)
  }()

  /// An observer of `window`'s notifications, with `watch` (this WindowWatch's address) as each
  /// one's context, or nil when Accessibility cannot reach the window, which is logged.
  @concurrent
  private nonisolated static func observe(_ window: CGWindowID, pid: pid_t, watch: UInt) async
    -> sending AXObserver?
  {
    let log = Logger(subsystem: "local.noren", category: "border")
    guard let getWindow else { return nil }
    let app = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    let copied = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
    guard copied == .success, let elements = value as? [AXUIElement] else {
      log.error("cannot list the windows of process \(pid): AXError \(copied.rawValue)")
      return nil
    }
    guard
      let element = elements.first(where: {
        var id: CGWindowID = 0
        return getWindow($0, &id) == .success && id == window
      })
    else {
      log.error("window \(window) is not among its app's Accessibility windows")
      return nil
    }
    var created: AXObserver?
    let made = AXObserverCreate(
      pid,
      { _, _, _, context in
        // The observer's source is on the main run loop. The context goes in as its address,
        // a plain number, since a pointer may not be sent there.
        let watch = UInt(bitPattern: context)
        MainActor.assumeIsolated {
          guard let context = UnsafeRawPointer(bitPattern: watch) else { return }
          Unmanaged<WindowWatch>.fromOpaque(context).takeUnretainedValue().onChange()
        }
      }, &created)
    guard made == .success, let observer = created else {
      log.error("cannot observe process \(pid): AXError \(made.rawValue)")
      return nil
    }
    let context = UnsafeMutableRawPointer(bitPattern: watch)
    let notifications = [
      (element, kAXMovedNotification), (element, kAXResizedNotification),
      (element, kAXUIElementDestroyedNotification), (element, kAXWindowMiniaturizedNotification),
      (app, kAXApplicationHiddenNotification), (app, kAXApplicationShownNotification),
    ]
    for (target, name) in notifications {
      let added = AXObserverAddNotification(observer, target, name as CFString, context)
      guard added == .success else {
        log.error(
          "cannot follow \(name, privacy: .public) of window \(window): AXError \(added.rawValue)")
        return nil
      }
    }
    return observer
  }
}
