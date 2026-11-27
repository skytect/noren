import NorenCore
import Testing

@Suite struct WindowLayersTests {
  func window(_ nativeId: UInt32?, _ layout: String, fullscreen: Bool = false) -> ListedWindow {
    ListedWindow(
      id: nativeId ?? 0, nativeId: nativeId, layout: layout, isFullscreen: fullscreen,
      workspace: "1", pid: 1, bundleId: nil, appName: "App", title: "")
  }

  @Test func `tiled windows go below and floating ones stay normal`() {
    let layers = WindowLayers(
      from: [], to: [window(1, "h_tiles"), window(2, "v_accordion"), window(3, "floating")])

    #expect(layers.below == [1, 2])
    #expect(layers.normal == [])
  }

  @Test func `a fullscreen window stays normal, to cover the floating ones`() {
    let layers = WindowLayers(from: [], to: [window(1, "h_tiles", fullscreen: true)])

    #expect(layers.below == [])
    #expect(layers.applied == [])
  }

  @Test func `a window floated or made fullscreen comes back to normal`() {
    let layers = WindowLayers(
      from: [1, 2, 3],
      to: [window(1, "floating"), window(2, "h_tiles", fullscreen: true), window(3, "v_tiles")])

    #expect(layers.below == [])
    #expect(layers.normal == [1, 2])
    #expect(layers.applied == [3])
  }

  @Test func `windows already below are not set again`() {
    #expect(WindowLayers(from: [1], to: [window(1, "h_tiles")]).isEmpty)
  }

  @Test func `with nothing known every window is set`() {
    let layers = WindowLayers(from: nil, to: [window(1, "h_tiles"), window(2, "floating")])

    #expect(layers.below == [1])
    #expect(layers.normal == [2])
  }

  @Test func `a window without a window server id is left be`() {
    #expect(WindowLayers(from: nil, to: [window(nil, "h_tiles")]).isEmpty)
  }

  @Test func `a minimized window goes back to normal`() {
    let layers = WindowLayers(from: [1], to: [window(1, "macos_native_minimized")])

    #expect(layers.normal == [1])
  }
}
