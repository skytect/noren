import Foundation
import NorenCore
import Testing

@Suite struct DwindleNestingTests {
  /// `aerospace list-windows --all --json --format` with the fields dwindle asks for, as AeroSpace
  /// prints it
  func listed(_ json: String) throws -> [ListedWindow] {
    try JSONDecoder().decode([ListedWindow].self, from: Data(json.utf8))
  }

  @Test func `a third tiled window side by side joins the window to its left`() throws {
    let windows = try listed(
      """
      [
        {"window-id" : 16, "window-id-native" : 208, "window-parent-container-layout" : "h_tiles", "workspace" : "1"},
        {"window-id" : 7, "window-id-native" : 73, "window-parent-container-layout" : "h_tiles", "workspace" : "1"},
        {"window-id" : 9, "window-id-native" : 119, "window-parent-container-layout" : "h_tiles", "workspace" : "1"}
      ]
      """)

    #expect(DwindleNesting(of: 9, among: windows) == .join(nativeId: 119, direction: .left))
  }

  @Test func `a new window in a stacked container joins the window above it`() throws {
    let windows = try listed(
      """
      [
        {"window-id" : 16, "window-id-native" : 208, "window-parent-container-layout" : "h_tiles", "workspace" : "2"},
        {"window-id" : 7, "window-id-native" : 73, "window-parent-container-layout" : "v_tiles", "workspace" : "2"},
        {"window-id" : 21, "window-id-native" : 340, "window-parent-container-layout" : "v_tiles", "workspace" : "2"}
      ]
      """)

    #expect(DwindleNesting(of: 21, among: windows) == .join(nativeId: 340, direction: .up))
  }

  @Test func `the second window of a workspace is left beside the first`() throws {
    let windows = try listed(
      """
      [
        {"window-id" : 16, "window-id-native" : 208, "window-parent-container-layout" : "h_tiles", "workspace" : "1"},
        {"window-id" : 9, "window-id-native" : 119, "window-parent-container-layout" : "h_tiles", "workspace" : "1"}
      ]
      """)

    #expect(DwindleNesting(of: 9, among: windows) == .leave(nativeId: 119, fade: true))
  }

  @Test func `tiled windows on other workspaces do not count`() throws {
    let windows = try listed(
      """
      [
        {"window-id" : 16, "window-id-native" : 208, "window-parent-container-layout" : "h_tiles", "workspace" : "1"},
        {"window-id" : 7, "window-id-native" : 73, "window-parent-container-layout" : "h_tiles", "workspace" : "6"},
        {"window-id" : 9, "window-id-native" : 119, "window-parent-container-layout" : "h_tiles", "workspace" : "6"}
      ]
      """)

    #expect(DwindleNesting(of: 16, among: windows) == .leave(nativeId: 208, fade: true))
  }

  @Test func `floating windows beside a second tiled one do not make it join`() throws {
    let windows = try listed(
      """
      [
        {"window-id" : 16, "window-id-native" : 208, "window-parent-container-layout" : "h_tiles", "workspace" : "3"},
        {"window-id" : 4, "window-id-native" : 52, "window-parent-container-layout" : "floating", "workspace" : "3"},
        {"window-id" : 9, "window-id-native" : 119, "window-parent-container-layout" : "h_tiles", "workspace" : "3"}
      ]
      """)

    #expect(DwindleNesting(of: 9, among: windows) == .leave(nativeId: 119, fade: true))
  }

  @Test func `a floating window is left and shown at once`() throws {
    let windows = try listed(
      """
      [
        {"window-id" : 16, "window-id-native" : 208, "window-parent-container-layout" : "h_tiles", "workspace" : "1"},
        {"window-id" : 7, "window-id-native" : 73, "window-parent-container-layout" : "h_tiles", "workspace" : "1"},
        {"window-id" : 4, "window-id-native" : 52, "window-parent-container-layout" : "floating", "workspace" : "1"}
      ]
      """)

    #expect(DwindleNesting(of: 4, among: windows) == .leave(nativeId: 52, fade: false))
  }

  @Test func `a window in an accordion is left and faded in`() throws {
    let windows = try listed(
      """
      [
        {"window-id" : 16, "window-id-native" : 208, "window-parent-container-layout" : "h_accordion", "workspace" : "1"},
        {"window-id" : 7, "window-id-native" : 73, "window-parent-container-layout" : "h_accordion", "workspace" : "1"},
        {"window-id" : 9, "window-id-native" : 119, "window-parent-container-layout" : "h_accordion", "workspace" : "1"}
      ]
      """)

    #expect(DwindleNesting(of: 9, among: windows) == .leave(nativeId: 119, fade: true))
  }

  @Test func `a window AeroSpace no longer lists is gone`() throws {
    let windows = try listed(
      """
      [
        {"window-id" : 16, "window-id-native" : 208, "window-parent-container-layout" : "h_tiles", "workspace" : "1"}
      ]
      """)

    #expect(DwindleNesting(of: 9, among: windows) == .gone)
  }

  @Test func `a listing with only the ids decodes without layout or workspace`() throws {
    let windows = try listed(
      """
      [
        {"window-id" : 16, "window-id-native" : 208}
      ]
      """)

    #expect(windows == [ListedWindow(id: 16, nativeId: 208)])
  }
}
