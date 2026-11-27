// Which workspace each window was on, kept so the windows go back after AeroSpace restarts:
// AeroSpace keeps its tree only while it runs, and a new process puts every window where its own
// rules say. Windows are known by their window server id, which outlives an AeroSpace process.

/// The workspace of each window AeroSpace listed, by window server id.
public struct WorkspacePlacements: Equatable, Sendable {
  /// A window to move back: AeroSpace's id of it, and the workspace it was on
  public struct Move: Equatable, Sendable {
    public let windowId: UInt32
    public let workspace: String

    public init(windowId: UInt32, workspace: String) {
      self.windowId = windowId
      self.workspace = workspace
    }
  }

  public let workspaces: [UInt32: String]

  /// The placements of `windows`, leaving out a window whose window server id AeroSpace lost.
  public init(_ windows: [ListedWindow]) {
    workspaces = Dictionary(
      windows.compactMap { window in window.nativeId.map { ($0, window.workspace) } },
      uniquingKeysWith: { first, _ in first })
  }

  /// The windows among `windows` on another workspace than recorded, each with the one to go back
  /// to. A window not recorded, opened since, stays where it is.
  public func moves(_ windows: [ListedWindow]) -> [Move] {
    windows.compactMap { window in
      guard let nativeId = window.nativeId, let workspace = workspaces[nativeId],
        workspace != window.workspace
      else { return nil }
      return Move(windowId: window.id, workspace: workspace)
    }
  }
}
