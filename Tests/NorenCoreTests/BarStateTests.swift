import NorenCore
import Testing

@Suite struct BarStateTests {
  // Two screens: workspaces 1 to 3 on the first, 4 and 5 on the second. 1 has a tiled terminal,
  // 3 a floating calculator, 4 a tiled browser and a tiled terminal; 2 and 5 are empty.
  let workspaces = [
    ListedWorkspace(name: "1", monitorId: 1, isVisible: false, isFocused: false),
    ListedWorkspace(name: "2", monitorId: 1, isVisible: true, isFocused: true),
    ListedWorkspace(name: "3", monitorId: 1, isVisible: false, isFocused: false),
    ListedWorkspace(name: "4", monitorId: 2, isVisible: true, isFocused: false),
    ListedWorkspace(name: "5", monitorId: 2, isVisible: false, isFocused: false),
  ]
  let used: Set<String> = ["1", "3", "4"]
  let windows = [
    Self.window(on: "1", layout: "h_tiles", pid: 10, bundleId: "com.example.terminal"),
    Self.window(on: "3", layout: "floating", pid: 20, bundleId: "com.example.calculator"),
    Self.window(on: "4", layout: "v_accordion", pid: 30, bundleId: "com.example.browser"),
    Self.window(on: "4", layout: "h_tiles", pid: 10, bundleId: "com.example.terminal"),
    Self.window(on: "4", layout: "h_tiles", pid: 31, bundleId: "com.example.browser"),
  ]

  /// A window of the app `bundleId` (process `pid`) on `workspace`, in a container laid out as
  /// `layout`. The bar does not read the other fields.
  static func window(
    on workspace: String, layout: String = "h_tiles", pid: Int32, bundleId: String?
  ) -> ListedWindow {
    ListedWindow(
      id: 1, nativeId: 1, layout: layout, workspace: workspace, pid: pid, bundleId: bundleId,
      appName: "app", title: "title")
  }

  func state(focused: ListedWindow? = nil) -> BarState {
    BarState(workspaces: workspaces, used: used, windows: windows, focused: focused)
  }

  @Test func `a screen's chips are its workspaces with windows and the one on screen`() {
    #expect(state().chips == [0: ["1", "2", "3"], 1: ["4"]])
  }

  @Test func `a screen is busy only when its workspace has a tiled window`() {
    #expect(state().busyScreens == [1])
  }

  @Test func `floating windows alone leave a workspace untiled`() {
    #expect(state().tiled == ["1", "4"])
  }

  @Test func `each workspace lists its apps once, in AeroSpace's order`() {
    #expect(
      state().apps["4"] == [.bundle("com.example.browser"), .bundle("com.example.terminal")])
  }

  @Test func `the focused screen is the focused workspace's`() {
    #expect(state().focusedScreen == 0)
  }

  @Test func `an app without a bundle id is keyed by its process`() {
    let focused = Self.window(on: "2", pid: 77, bundleId: nil)

    #expect(state(focused: focused).focused?.key == .process(77))
  }

  @Test func `showing a workspace on a screen focuses that screen`() {
    var state = state()

    state.show("1", onScreen: 1)

    #expect(state.visible[1] == "1")
    #expect(state.focusedScreen == 1)
  }

  @Test func `showing a tiled workspace blacks its screen`() {
    var state = state()

    state.show("1", onScreen: 0)

    #expect(state.busyScreens == [0, 1])
  }

  @Test func `showing an untiled workspace lifts the black`() {
    var state = state()

    state.show("5", onScreen: 1)

    #expect(state.busyScreens == [])
  }

  @Test func `a workspace gaining focus comes to the screen whose chips hold it`() {
    #expect(state().screen(receiving: "4") == 1)
  }

  @Test func `a workspace without a chip comes to the focused screen`() {
    #expect(state().screen(receiving: "5") == 0)
  }

  @Test func `stepping goes to the neighbouring chip`() {
    #expect(state().workspace(steppingBy: 1, onScreen: 0) == "3")
    #expect(state().workspace(steppingBy: -1, onScreen: 0) == "1")
  }

  @Test func `stepping stops at the ends`() {
    #expect(state().workspace(steppingBy: 2, onScreen: 0) == nil)
    #expect(state().workspace(steppingBy: 1, onScreen: 1) == nil)
  }
}
