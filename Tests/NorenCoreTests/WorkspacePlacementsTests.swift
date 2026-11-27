import NorenCore
import Testing

@Suite struct WorkspacePlacementsTests {
  /// AeroSpace's window `id` (window server id `nativeId`) on `workspace`
  func window(_ id: UInt32, _ nativeId: UInt32?, on workspace: String) -> ListedWindow {
    ListedWindow(
      id: id, nativeId: nativeId, layout: "h_tiles", workspace: workspace, pid: 1, bundleId: nil,
      appName: "App", title: "")
  }

  @Test func `a window AeroSpace put elsewhere after a restart goes back to its workspace`() {
    let before = WorkspacePlacements([window(16, 208, on: "6")])

    #expect(before.moves([window(1, 208, on: "1")]) == [.init(windowId: 1, workspace: "6")])
  }

  @Test func `a window still on its workspace stays`() {
    let before = WorkspacePlacements([window(16, 208, on: "6")])

    #expect(before.moves([window(1, 208, on: "6")]) == [])
  }

  @Test func `a window opened since stays where it is`() {
    let before = WorkspacePlacements([window(16, 208, on: "6")])

    #expect(before.moves([window(2, 340, on: "1")]) == [])
  }

  @Test func `a window whose window server id AeroSpace lost is not recorded`() {
    #expect(WorkspacePlacements([window(16, nil, on: "6")]).workspaces == [:])
  }
}
