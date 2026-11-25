// A workspace as `aerospace list-workspaces --json --format ListedWorkspace.format` lists it. The
// format asks for every field any part of noren reads, so every listing of workspaces decodes to
// this one type.

/// One workspace in AeroSpace's list-workspaces output.
public struct ListedWorkspace: Decodable, Equatable, Sendable {
  /// The `--format` that lists every field below.
  public static let format =
    "%{workspace} %{monitor-appkit-nsscreen-screens-id} %{workspace-is-visible}"
    + " %{workspace-is-focused}"

  enum CodingKeys: String, CodingKey {
    case name = "workspace"
    case monitorId = "monitor-appkit-nsscreen-screens-id"
    case isVisible = "workspace-is-visible"
    case isFocused = "workspace-is-focused"
  }

  public let name: String
  /// The workspace's screen: its place in NSScreen.screens, counted from 1.
  public let monitorId: Int
  /// On a screen, focused or not
  public let isVisible: Bool
  public let isFocused: Bool

  public init(name: String, monitorId: Int, isVisible: Bool, isFocused: Bool) {
    self.name = name
    self.monitorId = monitorId
    self.isVisible = isVisible
    self.isFocused = isFocused
  }
}
