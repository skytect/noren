import Foundation
import NorenCore
import Testing

@Suite struct WorkspacePlacementsTests {
  /// AeroSpace's window `id` (window server id `nativeId`) on `workspace`, laid out as `layout`
  func window(_ id: UInt32, _ nativeId: UInt32?, on workspace: String, _ layout: String = "h_tiles")
    -> ListedWindow
  {
    ListedWindow(
      id: id, nativeId: nativeId, layout: layout, workspace: workspace, pid: 1, bundleId: nil,
      appName: "App", title: "")
  }

  @Test func `a window AeroSpace put elsewhere after a restart goes back to its workspace`() {
    let before = WorkspacePlacements([window(16, 208, on: "6")], aeroSpace: 100)

    #expect(before.moves([window(1, 208, on: "1")]) == [.init(windowId: 1, workspace: "6")])
  }

  @Test func `a window AeroSpace laid out as an accordion at its start gets its layout back`() {
    let before = WorkspacePlacements([window(16, 208, on: "1", "h_tiles")], aeroSpace: 100)

    #expect(
      before.moves([window(1, 208, on: "1", "h_accordion")])
        == [.init(windowId: 1, layout: "h_tiles")])
  }

  @Test func `a window still where it was stays`() {
    let before = WorkspacePlacements([window(16, 208, on: "6")], aeroSpace: 100)

    #expect(before.moves([window(1, 208, on: "6")]) == [])
  }

  @Test func `a window minimized before keeps the layout AeroSpace gives it`() {
    let before = WorkspacePlacements(
      [window(16, 208, on: "6", "macos_native_minimized")], aeroSpace: 100)

    #expect(before.moves([window(1, 208, on: "6", "h_tiles")]) == [])
  }

  @Test func `a window opened since stays where it is`() {
    let before = WorkspacePlacements([window(16, 208, on: "6")], aeroSpace: 100)

    #expect(before.moves([window(2, 340, on: "1")]) == [])
  }

  @Test func `a window whose window server id AeroSpace lost is not recorded`() {
    #expect(WorkspacePlacements([window(16, nil, on: "6")], aeroSpace: 100).placements == [])
  }

  @Test func `placements saved by one noren put windows back for the next`() throws {
    let saved = WorkspacePlacements([window(16, 208, on: "6")], aeroSpace: 100)

    let loaded = try JSONDecoder().decode(
      WorkspacePlacements.self, from: try JSONEncoder().encode(saved))

    #expect(loaded.moves([window(1, 208, on: "1")]) == [.init(windowId: 1, workspace: "6")])
  }
}
