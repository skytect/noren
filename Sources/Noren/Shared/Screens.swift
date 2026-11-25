import AppKit

extension NSScreen {
  /// The display this screen shows. NSScreen objects are made afresh on each lookup, so screens
  /// are compared by this.
  var displayID: CGDirectDisplayID {
    (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
  }

  /// The screen AeroSpace numbers `id` (from 1) with %{monitor-appkit-nsscreen-screens-id}: its
  /// place in NSScreen.screens. nil when there is no such screen any more.
  static func aeroSpaceMonitor(_ id: Int) -> NSScreen? {
    screens.indices.contains(id - 1) ? screens[id - 1] : nil
  }
}
