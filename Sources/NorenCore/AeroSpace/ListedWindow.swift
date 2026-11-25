// A window as `aerospace list-windows --json --format ListedWindow.format` lists it. The format
// asks for every field any part of noren reads, so every listing of windows decodes to this one
// type.

/// One window in AeroSpace's list-windows output.
public struct ListedWindow: Decodable, Equatable, Sendable {
  /// The `--format` that lists every field below.
  public static let format =
    "%{window-id} %{window-id-native} %{window-parent-container-layout} %{workspace}"
    + " %{app-pid} %{app-bundle-id} %{app-name} %{window-title}"

  /// What AeroSpace prints for `%{app-bundle-id}` when the app has no bundle id
  /// (AeroSpace's Sources/AppBundle/command/format.swift).
  static let noBundleId = "NULL-APP-BUNDLE-ID"

  enum CodingKeys: String, CodingKey {
    case id = "window-id"
    case nativeId = "window-id-native"
    case layout = "window-parent-container-layout"
    case workspace
    case pid = "app-pid"
    case bundleId = "app-bundle-id"
    case appName = "app-name"
    case title = "window-title"
  }

  /// AeroSpace's id of the window
  public let id: UInt32
  /// The window server's id of the window (CGWindowID)
  public let nativeId: UInt32
  /// The layout of the container the window is in: `h_tiles`, `v_tiles`, `h_accordion`,
  /// `v_accordion` or `floating`; AeroSpace names other values for a window it does not lay out,
  /// such as a minimized one
  public let layout: String
  public let workspace: String
  /// The process of the window's app
  public let pid: Int32
  /// The app's bundle id, nil for an app without one
  public let bundleId: String?
  public let appName: String
  public let title: String

  public init(
    id: UInt32, nativeId: UInt32, layout: String, workspace: String, pid: Int32,
    bundleId: String?, appName: String, title: String
  ) {
    self.id = id
    self.nativeId = nativeId
    self.layout = layout
    self.workspace = workspace
    self.pid = pid
    self.bundleId = bundleId
    self.appName = appName
    self.title = title
  }

  /// Decodes a window, with `bundleId` nil when AeroSpace gives none: null, left out, or its
  /// placeholder for an app without one.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
    self.init(
      id: try container.decode(UInt32.self, forKey: .id),
      nativeId: try container.decode(UInt32.self, forKey: .nativeId),
      layout: try container.decode(String.self, forKey: .layout),
      workspace: try container.decode(String.self, forKey: .workspace),
      pid: try container.decode(Int32.self, forKey: .pid),
      bundleId: bundleId == Self.noBundleId ? nil : bundleId,
      appName: try container.decode(String.self, forKey: .appName),
      title: try container.decode(String.self, forKey: .title))
  }
}
