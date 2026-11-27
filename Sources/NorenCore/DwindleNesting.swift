// Where a new window goes in a dwindle layout. AeroSpace puts a new window right after the focused
// one in the same container, so every window would end up side by side. Joining it with that
// window instead nests the two across the container, alternating side-by-side and stacked. The
// second window of a workspace is left beside the first: that first split follows the screen's
// longer side. A window that was there before AeroSpace started is left be: AeroSpace reports
// every window it finds at its start as detected, but they are not new, and Restore puts them back
// where they were.

/// What becomes of a new window: joined with the window before it, left where AeroSpace put it, or
/// nothing when AeroSpace no longer lists it.
public enum DwindleNesting: Equatable, Sendable {
  /// Toward where a window joins the one before it, as `aerospace join-with` takes it
  public enum Direction: String, Sendable {
    case left, up
  }

  /// `aerospace join-with` the window toward `direction`, then show it faded in
  case join(nativeId: UInt32, direction: Direction)
  /// Left in place, then shown faded in, or at once (`fade` false) when it floats: nothing made
  /// room for it
  case leave(nativeId: UInt32, fade: Bool)
  /// AeroSpace does not list the window (it closed already), or has lost its window server id:
  /// nothing to place or show
  case gone

  /// The nesting of AeroSpace's window `window`, reported new, among every window AeroSpace lists
  /// (`windows`, with their layouts and workspaces); `existing` holds the window server ids of the
  /// windows there before AeroSpace started.
  public init(of window: UInt32, among windows: [ListedWindow], existing: Set<UInt32> = []) {
    guard let new = windows.first(where: { $0.id == window }), let nativeId = new.nativeId else {
      self = .gone
      return
    }
    if existing.contains(nativeId) {
      self = .leave(nativeId: nativeId, fade: false)
      return
    }
    let direction: Direction
    switch new.layout {
    case "h_tiles": direction = .left
    case "v_tiles": direction = .up
    default:
      // Floating or accordion
      self = .leave(nativeId: nativeId, fade: new.layout != "floating")
      return
    }
    let tiledBeside = windows.count {
      $0.workspace == new.workspace && $0.layout.hasSuffix("_tiles")
    }
    self =
      tiledBeside > 2
      ? .join(nativeId: nativeId, direction: direction)
      : .leave(nativeId: nativeId, fade: true)
  }
}
