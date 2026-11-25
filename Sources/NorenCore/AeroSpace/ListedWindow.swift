// A window as `aerospace list-windows --json` lists it, with the fields noren asks for in its
// --format. Fields left out of the format are nil.

/// One window in AeroSpace's list-windows output.
public struct ListedWindow: Decodable, Equatable, Sendable {
  enum CodingKeys: String, CodingKey {
    case id = "window-id"
    case nativeId = "window-id-native"
    case layout = "window-parent-container-layout"
    case workspace
  }

  /// AeroSpace's id of the window
  public let id: UInt32
  /// The window server's id of the window (CGWindowID)
  public let nativeId: UInt32
  /// The layout of the container the window is in: `h_tiles`, `v_tiles`, `h_accordion`,
  /// `v_accordion` or `floating`
  public let layout: String?
  public let workspace: String?

  public init(id: UInt32, nativeId: UInt32, layout: String? = nil, workspace: String? = nil) {
    self.id = id
    self.nativeId = nativeId
    self.layout = layout
    self.workspace = workspace
  }
}
