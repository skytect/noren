import NorenCore
import Testing

@Suite struct SymbolicHotKeyTests {
  /// "Show Notification Center" on fn-F5 (key code 96), as Keyboard settings stores it.
  let hotKeys: [String: Any] = [
    "163": [
      "enabled": true, "value": ["parameters": [65535, 96, 8_388_608], "type": "standard"],
    ],
    "64": ["enabled": false, "value": ["parameters": [32, 49, 1_048_576], "type": "standard"]],
  ]

  @Test func `an enabled shortcut gives its key code and modifiers`() {
    #expect(
      SymbolicHotKey(action: SymbolicHotKey.showNotificationCenter, in: hotKeys)
        == SymbolicHotKey(keyCode: 96, modifiers: 0x80_0000))
  }

  @Test func `a disabled shortcut is no shortcut`() {
    #expect(SymbolicHotKey(action: 64, in: hotKeys) == nil)
  }

  @Test func `an action without an entry has no shortcut`() {
    #expect(SymbolicHotKey(action: 160, in: hotKeys) == nil)
  }

  @Test func `an entry of another shape is no shortcut`() {
    let odd: [String: Any] = ["163": ["enabled": true, "value": ["parameters": [96]]]]

    #expect(SymbolicHotKey(action: 163, in: odd) == nil)
  }
}
