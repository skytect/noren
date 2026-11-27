// Where each window was, kept so the windows go back after AeroSpace restarts: AeroSpace keeps its
// tree only while it runs, and a new process puts every window on the focused workspace, laid out
// as an accordion when there are more than three (smartLayoutAtStartup in
// Sources/AppBundle/initAppBundle.swift). Windows are known by their window server id, which
// outlives an AeroSpace process and noren's too: the placements are saved with the snapshot.

/// The workspace and layout of each window AeroSpace listed, by window server id, under one
/// AeroSpace process.
public struct WorkspacePlacements: Codable, Equatable, Sendable {
  /// Where a window was
  public struct Placement: Codable, Equatable, Sendable {
    public let window: UInt32
    public let workspace: String
    /// The layout of the window's container, as `aerospace layout` takes it
    public let layout: String
  }

  /// A window to put back: AeroSpace's id of it, the workspace it was on when that changed, and
  /// the layout it had when that changed
  public struct Move: Equatable, Sendable {
    public let windowId: UInt32
    public let workspace: String?
    public let layout: String?

    public init(windowId: UInt32, workspace: String? = nil, layout: String? = nil) {
      self.windowId = windowId
      self.workspace = workspace
      self.layout = layout
    }
  }

  /// The layouts `aerospace layout` sets; a window in any other (minimized, of a hidden app) is
  /// left in it
  private static let settable: Set = [
    "h_tiles", "v_tiles", "h_accordion", "v_accordion", "floating",
  ]

  /// The AeroSpace process the windows were listed under, or that they were put back under
  public var aeroSpace: Int32
  public let placements: [Placement]

  /// The placements of `windows` under the AeroSpace process `aeroSpace`, leaving out a window
  /// whose window server id AeroSpace lost.
  public init(_ windows: [ListedWindow], aeroSpace: Int32) {
    self.aeroSpace = aeroSpace
    var seen = Set<UInt32>()
    placements = windows.compactMap { window in
      guard let id = window.nativeId, seen.insert(id).inserted else { return nil }
      return Placement(window: id, workspace: window.workspace, layout: window.layout)
    }
  }

  /// The windows among `windows` not where they were recorded, each with what to put back. A
  /// window not recorded, opened since, stays as it is.
  public func moves(_ windows: [ListedWindow]) -> [Move] {
    let recorded = Dictionary(placements.map { ($0.window, $0) }, uniquingKeysWith: { a, _ in a })
    return windows.compactMap { window in
      guard let nativeId = window.nativeId, let was = recorded[nativeId] else { return nil }
      let workspace = was.workspace != window.workspace ? was.workspace : nil
      let layout =
        was.layout != window.layout && Self.settable.contains(was.layout) ? was.layout : nil
      guard workspace != nil || layout != nil else { return nil }
      return Move(windowId: window.id, workspace: workspace, layout: layout)
    }
  }
}
