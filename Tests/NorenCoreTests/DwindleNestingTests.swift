import NorenCore
import Testing

@Suite struct DwindleNestingTests {
  /// AeroSpace's window `id` (window server id `nativeId`) on `workspace`, in a container laid out
  /// as `layout`. Dwindle does not read the other fields.
  func window(_ id: UInt32, _ nativeId: UInt32, _ layout: String, on workspace: String)
    -> ListedWindow
  {
    ListedWindow(
      id: id, nativeId: nativeId, layout: layout, workspace: workspace, pid: 1, bundleId: nil,
      appName: "app", title: "title")
  }

  @Test func `a third tiled window side by side joins the window to its left`() {
    let windows = [
      window(16, 208, "h_tiles", on: "1"),
      window(7, 73, "h_tiles", on: "1"),
      window(9, 119, "h_tiles", on: "1"),
    ]

    #expect(DwindleNesting(of: 9, among: windows) == .join(nativeId: 119, direction: .left))
  }

  @Test func `a window there before AeroSpace started is left where it is`() {
    let windows = [
      window(16, 208, "h_tiles", on: "1"),
      window(7, 73, "h_tiles", on: "1"),
      window(9, 119, "h_tiles", on: "1"),
    ]

    #expect(
      DwindleNesting(of: 9, among: windows, existing: [208, 73, 119])
        == .leave(nativeId: 119, fade: false))
  }

  @Test func `a new window in a stacked container joins the window above it`() {
    let windows = [
      window(16, 208, "h_tiles", on: "2"),
      window(7, 73, "v_tiles", on: "2"),
      window(21, 340, "v_tiles", on: "2"),
    ]

    #expect(DwindleNesting(of: 21, among: windows) == .join(nativeId: 340, direction: .up))
  }

  @Test func `the second window of a workspace is left beside the first`() {
    let windows = [
      window(16, 208, "h_tiles", on: "1"),
      window(9, 119, "h_tiles", on: "1"),
    ]

    #expect(DwindleNesting(of: 9, among: windows) == .leave(nativeId: 119, fade: true))
  }

  @Test func `tiled windows on other workspaces do not count`() {
    let windows = [
      window(16, 208, "h_tiles", on: "1"),
      window(7, 73, "h_tiles", on: "6"),
      window(9, 119, "h_tiles", on: "6"),
    ]

    #expect(DwindleNesting(of: 16, among: windows) == .leave(nativeId: 208, fade: true))
  }

  @Test func `floating windows beside a second tiled one do not make it join`() {
    let windows = [
      window(16, 208, "h_tiles", on: "3"),
      window(4, 52, "floating", on: "3"),
      window(9, 119, "h_tiles", on: "3"),
    ]

    #expect(DwindleNesting(of: 9, among: windows) == .leave(nativeId: 119, fade: true))
  }

  @Test func `a floating window is left and shown at once`() {
    let windows = [
      window(16, 208, "h_tiles", on: "1"),
      window(7, 73, "h_tiles", on: "1"),
      window(4, 52, "floating", on: "1"),
    ]

    #expect(DwindleNesting(of: 4, among: windows) == .leave(nativeId: 52, fade: false))
  }

  @Test func `a window in an accordion is left and faded in`() {
    let windows = [
      window(16, 208, "h_accordion", on: "1"),
      window(7, 73, "h_accordion", on: "1"),
      window(9, 119, "h_accordion", on: "1"),
    ]

    #expect(DwindleNesting(of: 9, among: windows) == .leave(nativeId: 119, fade: true))
  }

  @Test func `a window AeroSpace no longer lists is gone`() {
    let windows = [
      window(16, 208, "h_tiles", on: "1")
    ]

    #expect(DwindleNesting(of: 9, among: windows) == .gone)
  }
}
