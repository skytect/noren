import NorenCore

extension AeroSpaceClient {
  /// The workspaces the `list-workspaces` command `args` lists, one name a line.
  nonisolated func workspaceNames(_ args: [String]) async throws(AeroSpaceError) -> [String] {
    try await run(["list-workspaces"] + args).split(whereSeparator: \.isNewline).map(String.init)
  }
}
