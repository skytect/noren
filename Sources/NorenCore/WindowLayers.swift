// Floating windows stay above tiled ones. Every tiled window goes one level down, to the
// backstop menu level where yabai puts the windows it manages (window_manager_set_window_layer in
// src/window_manager.c), so floating windows, dialogs and every window AeroSpace leaves alone stay
// above them at the normal level, the focused tiled window included. A window AeroSpace fills its
// monitor with (`fullscreen`) stays at the normal level: focused, it covers the floating ones.

/// Which windows go below, and the changes from the ones already there.
public struct WindowLayers: Equatable, Sendable {
  /// The window server ids of the windows to put below
  public let below: [UInt32]
  /// The window server ids of the windows to bring back to the normal level
  public let normal: [UInt32]
  /// Every window below once these are applied
  public let applied: Set<UInt32>

  /// The changes from `applied`, the windows already below (nil when unknown: every listed window
  /// is set then), to what `windows` asks for. Windows AeroSpace has lost the id of are left be.
  public init(from applied: Set<UInt32>?, to windows: [ListedWindow]) {
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
    below = wanted.subtracting(applied ?? []).sorted()
    normal = (applied.map { $0.intersection(others) } ?? others).sorted()
    self.applied = wanted
  }

  /// Whether nothing changes
  public var isEmpty: Bool { below.isEmpty && normal.isEmpty }

  /// Whether `window` goes below the normal level: tiled, and not filling its monitor
  public static func goesBelow(_ window: ListedWindow) -> Bool {
    window.layout.hasSuffix("_tiles") || window.layout.hasSuffix("_accordion")
      ? !window.isFullscreen : false
  }
}
