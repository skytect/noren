// macOS's keyboard shortcuts for its own actions ("symbolic hot keys"), as Keyboard settings
// stores them: com.apple.symbolichotkeys' AppleSymbolicHotKeys, a dictionary from each action's
// number, as a string, to
//
//   { enabled = 1; value = { parameters = (character, key code, modifiers); type = standard; }; }
//
// where the character is 65535 for a key without one (an F key), and the modifiers are the same
// bits as CGEventFlags' (shift 0x20000, control 0x40000, option 0x80000, command 0x100000, fn
// 0x800000).

/// A key with its modifiers, as macOS binds one of its actions to it.
public struct SymbolicHotKey: Equatable, Sendable {
  /// "Show Notification Center".
  public static let showNotificationCenter = 163

  public let keyCode: UInt16
  /// CGEventFlags bits.
  public let modifiers: UInt64

  public init(keyCode: UInt16, modifiers: UInt64) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  /// The enabled shortcut for action `action` in `hotKeys` (AppleSymbolicHotKeys), or nil when
  /// it has none, it is off, or it is not in the shape above.
  public init?(action: Int, in hotKeys: [String: Any]) {
    guard let entry = hotKeys[String(action)] as? [String: Any],
      (entry["enabled"] as? Bool) == true,
      let value = entry["value"] as? [String: Any],
      let parameters = value["parameters"] as? [Int], parameters.count == 3,
      let keyCode = UInt16(exactly: parameters[1]),
      let modifiers = UInt64(exactly: parameters[2])
    else { return nil }
    self.init(keyCode: keyCode, modifiers: modifiers)
  }
}
