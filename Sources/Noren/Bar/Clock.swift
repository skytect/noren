// The bar's clock: its text, which changes on a timer set for each minute's start, and the click
// that opens Notification Center. macOS has no call that opens it, so the click presses the
// shortcut macOS binds to "Show Notification Center" (SymbolicHotKey), read at each click so a
// change in Keyboard settings counts at once, or the key bar.notification-center-key names.
import AppKit
import NorenCore
import os

final class Clock {
  private let log = Logger(subsystem: "local.noren", category: "bar")
  /// bar.notification-center-key; nil for macOS's own shortcut.
  private let configuredKey: Int?
  private let formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE d MMM  HH:mm"
    return formatter
  }()
  private var reportedNoShortcut = false
  private var changed: () -> Void = {}
  private var timer: Timer?

  init(configuredKey: Int?) {
    self.configuredKey = configuredKey
  }

  /// Calls `changed` whenever the time the clock shows changes: at each minute's start, and when
  /// the Mac wakes or its clock or time zone is set, which a timer does not follow.
  func start(changed: @escaping () -> Void) {
    self.changed = changed
    let center = NotificationCenter.default
    for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
      center.addObserver(forName: name, object: nil, queue: .main) { [unowned self] _ in
        MainActor.assumeIsolated { reset() }
      }
    }
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [unowned self] _ in
      MainActor.assumeIsolated { reset() }
    }
    schedule()
  }

  /// Shows the time afresh, and sets the timer again from now.
  private func reset() {
    NSTimeZone.resetSystemTimeZone()
    formatter.timeZone = .current
    changed()
    schedule()
  }

  /// Sets the timer for the next minute's start.
  private func schedule() {
    timer?.invalidate()
    let now = Date()
    let next =
      Calendar.current.nextDate(
        after: now, matching: DateComponents(second: 0), matchingPolicy: .nextTime)
      ?? now.addingTimeInterval(60)
    let timer = Timer(fire: next, interval: 0, repeats: false) { [unowned self] _ in
      MainActor.assumeIsolated {
        changed()
        schedule()
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  /// The time as the bar shows it.
  func text() -> String {
    formatter.string(from: Date())
  }

  /// Opens Notification Center by pressing its shortcut; does nothing, logging that once, when
  /// it has none.
  func openNotificationCenter() {
    guard let shortcut = shortcut() else {
      if !reportedNoShortcut {
        reportedNoShortcut = true
        log.notice(
          """
          the clock cannot open Notification Center: no shortcut is set for it in Keyboard \
          settings, and bar.notification-center-key is not set
          """)
      }
      return
    }
    for down in [true, false] {
      let event = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.keyCode, keyDown: down)
      event?.flags = CGEventFlags(rawValue: shortcut.modifiers)
      event?.post(tap: .cghidEventTap)
    }
  }

  /// The shortcut to press. A configured key is pressed with fn, as an F key is.
  private func shortcut() -> SymbolicHotKey? {
    if let configuredKey {
      return SymbolicHotKey(
        keyCode: UInt16(configuredKey), modifiers: CGEventFlags.maskSecondaryFn.rawValue)
    }
    let hotKeys =
      CFPreferencesCopyAppValue(
        "AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString)
      as? [String: Any]
    return hotKeys.flatMap {
      SymbolicHotKey(action: SymbolicHotKey.showNotificationCenter, in: $0)
    }
  }
}
