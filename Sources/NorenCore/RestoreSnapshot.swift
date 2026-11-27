// The apps and windows a session had, saved so they can be brought back after a restart or a
// logout. The JSON is the snapshot file's format (snapshot.json in noren's Application Support
// folder); a snapshot saved by one version of noren is restored by the next.
import Foundation

/// The regular apps that were running, and each one's windows.
public struct RestoreSnapshot: Codable, Equatable, Sendable {
  public struct App: Codable, Equatable, Sendable {
    public var bundleId: String
    public var windows: [Window]

    public init(bundleId: String, windows: [Window]) {
      self.bundleId = bundleId
      self.windows = windows
    }
  }

  public struct Window: Codable, Equatable, Sendable {
    /// The AeroSpace workspace the window was on.
    public var workspace: String
    public var title: String

    public init(workspace: String, title: String) {
      self.workspace = workspace
      self.title = title
    }
  }

  /// The boot it was taken in (kern.bootsessionuuid), new at each boot.
  public var boot: String
  public var apps: [App]
  /// Whether it was taken as the session ended (a logout, restart or shutdown).
  public var ending: Bool
  /// Where each window was under the AeroSpace process noren last saw before it restarted, nil in
  /// a snapshot from before noren kept them here
  public var placements: WorkspacePlacements?

  public init(boot: String, apps: [App], ending: Bool) {
    self.boot = boot
    self.apps = apps
    self.ending = ending
  }

  /// The snapshot of `apps`, in their order, each with its windows among `windows` (in theirs).
  /// Windows of other apps are left out.
  public init(boot: String, apps: [String], windows: [(appId: String?, window: Window)]) {
    var byApp = Dictionary(apps.map { ($0, [Window]()) }, uniquingKeysWith: { first, _ in first })
    for (appId, window) in windows {
      if let appId { byApp[appId]?.append(window) }
    }
    self.init(
      boot: boot, apps: apps.map { App(bundleId: $0, windows: byApp[$0] ?? []) }, ending: false)
  }

  /// Whether noren, starting in the boot `boot`, brings this snapshot's apps back: when it ended
  /// a session, or is from an earlier boot (a crash or power loss marks no end).
  public func isRestored(inBoot boot: String) -> Bool {
    ending || self.boot != boot
  }

  public init(json: Data) throws {
    self = try JSONDecoder().decode(Self.self, from: json)
  }

  public func json() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(self)
  }
}
