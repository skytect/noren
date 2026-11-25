// Which workspaces the strip shows (Noren/Strip): the focused screen's workspaces that have
// windows, and the focused one. For a swipe it also holds the first empty workspace after the last
// of them, so swiping past the last used workspace opens a fresh one, and stops there.

/// A workspace as `list-workspaces --json --format ListedWorkspace.format` lists it.
public struct ListedWorkspace: Decodable, Equatable, Sendable {
  enum CodingKeys: String, CodingKey {
    case name = "workspace"
    case isFocused = "workspace-is-focused"
    case monitorId = "monitor-appkit-nsscreen-screens-id"
  }

  /// The `--format` that lists these fields.
  public static let format =
    "%{workspace} %{workspace-is-focused} %{monitor-appkit-nsscreen-screens-id}"

  public let name: String
  public let isFocused: Bool
  /// The workspace's screen: its place in NSScreen.screens, counted from 1.
  public let monitorId: Int

  public init(name: String, isFocused: Bool, monitorId: Int) {
    self.name = name
    self.isFocused = isFocused
    self.monitorId = monitorId
  }
}

/// The workspaces in the strip, in AeroSpace's order.
public struct StripWorkspaces: Equatable, Sendable {
  public let names: [String]
  /// The focused workspace's index in `names`.
  public let focused: Int
  /// The screen the strip is on, as ListedWorkspace counts screens.
  public let monitorId: Int

  public init(names: [String], focused: Int, monitorId: Int) {
    self.names = names
    self.focused = focused
    self.monitorId = monitorId
  }

  /// The strip for the focused screen's workspaces `listed`, of which `used` have windows; with
  /// the first empty workspace after the last used one when `withSpare`. nil when none of
  /// `listed` is focused.
  public init?(listed: [ListedWorkspace], used: Set<String>, withSpare: Bool) {
    var names: [String] = []
    var focused: Int?
    var monitorId = 0
    var spare: String?
    for workspace in listed {
      if workspace.isFocused || used.contains(workspace.name) {
        if workspace.isFocused {
          focused = names.count
          monitorId = workspace.monitorId
        }
        names.append(workspace.name)
        spare = nil
      } else if spare == nil {
        spare = workspace.name
      }
    }
    guard let focused else { return nil }
    if withSpare, let spare { names.append(spare) }
    self.init(names: names, focused: focused, monitorId: monitorId)
  }
}
