// Floating windows stay above tiled ones. Every tiled window goes below, to the backstop menu
// sublevel where yabai puts the windows it manages (window_manager_set_window_layer in
// src/window_manager.c): still at the normal level, but under every other window there. Floating
// windows, dialogs and every window AeroSpace leaves alone stay above them, the focused tiled
// window included. A window AeroSpace fills its monitor with (`fullscreen`) is not put below:
// focused, it covers the floating ones.

/// The changes that put the right windows below.
public struct WindowLayers: Equatable, Sendable {
  /// The window server ids of the windows to put below
  public let below: [UInt32]
  /// The window server ids of the windows to bring back to the normal level
  public let normal: [UInt32]

  /// The changes from `current`, the windows below now, to what `windows` asks for. Windows
  /// AeroSpace has lost the id of are left be.
  public init(from current: Set<UInt32>, to windows: [ListedWindow]) {
    var wanted = Set<UInt32>()
    var others = Set<UInt32>()
    for window in windows {
      guard let id = window.nativeId else { continue }
      if Self.goesBelow(window) {
        wanted.insert(id)
      } else {
        others.insert(id)
      }
    }
    below = wanted.subtracting(current).sorted()
    normal = current.intersection(others).sorted()
  }

  /// Whether nothing changes
  public var isEmpty: Bool { below.isEmpty && normal.isEmpty }

  /// Whether `window` goes below the other windows: tiled, and not filling its monitor
  public static func goesBelow(_ window: ListedWindow) -> Bool {
    window.layout.hasSuffix("_tiles") || window.layout.hasSuffix("_accordion")
      ? !window.isFullscreen : false
  }
}
