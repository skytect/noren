// The bar's clock: its text, and the click that opens Notification Center. macOS has no call
// that opens it, so the click presses the shortcut macOS binds to "Show Notification Center"
// (SymbolicHotKey), read at each click so a change in Keyboard settings counts at once, or the
// key bar.notification-center-key names.
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

  init(configuredKey: Int?) {
    self.configuredKey = configuredKey
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
