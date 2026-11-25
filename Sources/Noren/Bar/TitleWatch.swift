// The focused window's title changes without an AeroSpace event: a browser's tab, a terminal's
// command. This follows it through Accessibility's title-changed notification on that window,
// so the bar reads AeroSpace afresh only when the title has changed.
//
// Accessibility is the permission noren's border and drag already need. Without it, the title is
// read only as AeroSpace's events come.
import ApplicationServices
import os

final class TitleWatch {
  /// How long an Accessibility call to an app may take before it is given up: an app that hangs
  /// must not hold the bar.
  private static let messagingTimeout: Float = 0.25

  private let log = Logger(subsystem: "local.noren", category: "bar")
  private let changed: () -> Void
  /// The followed process's observer, and the window its notification is on.
  private var observer: (pid: pid_t, observer: AXObserver)?
  private var window: AXUIElement?
  private var reportedUntrusted = false

  /// Calls `changed` whenever the followed window's title changes.
  init(changed: @escaping () -> Void) {
    self.changed = changed
  }

  /// Follows the title of process `pid`'s focused window; nil follows none.
  func follow(pid: pid_t?) {
    guard let pid else {
      stop()
      return
    }
    guard AXIsProcessTrusted() else {
      if !reportedUntrusted {
        reportedUntrusted = true
        log.notice(
          "without Accessibility, the bar sees a window's new title only when AeroSpace has news")
      }
      return
    }
    if observer?.pid != pid {
      stop()
      guard let made = makeObserver(pid) else { return }
      observer = (pid, made)
    }
    let focused = focusedWindow(pid)
    if let focused, let window, CFEqual(focused, window) { return }
    unwatchWindow()
    guard let focused, let observer else { return }
    let status = AXObserverAddNotification(
      observer.observer, focused, kAXTitleChangedNotification as CFString,
      Unmanaged.passUnretained(self).toOpaque())
    if status == .success {
      window = focused
    } else {
      log.debug("cannot follow process \(pid)'s window title: AXError \(status.rawValue)")
    }
  }

  private func focusedWindow(_ pid: pid_t) -> AXUIElement? {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value)
        == .success,
      let value, CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return (value as! AXUIElement)
  }

  private func makeObserver(_ pid: pid_t) -> AXObserver? {
    var observer: AXObserver?
    let status = AXObserverCreate(
      pid,
      { _, _, _, context in
        MainActor.assumeIsolated {
          Unmanaged<TitleWatch>.fromOpaque(context!).takeUnretainedValue().changed()
        }
      }, &observer)
    guard status == .success, let observer else {
      log.debug("cannot observe process \(pid): AXError \(status.rawValue)")
      return nil
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    return observer
  }

  private func unwatchWindow() {
    if let window, let observer {
      AXObserverRemoveNotification(
        observer.observer, window, kAXTitleChangedNotification as CFString)
    }
    window = nil
  }

  private func stop() {
    unwatchWindow()
    if let observer {
      CFRunLoopRemoveSource(
        CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer.observer), .defaultMode)
    }
    observer = nil
  }
}
