import CoreGraphics
import NorenCore
import Testing

@Suite struct DisplayArrangementTests {
  /// A 1800x1169 built-in screen as the main display
  let home = CGRect(x: 0, y: 0, width: 1800, height: 1169)
  let monitor = DisplayPlacement.Display.monitor(vendor: 0x10ac, model: 41234, serial: 7)
  let monitorSize = CGSize(width: 3008, height: 1692)
  let iPadSize = CGSize(width: 1366, height: 1024)

  @Test func `a monitor above, left-aligned, has its bottom-left corner on the screen's top-left`()
  {
    let rule = DisplayPlacement(display: monitor, position: .above, align: .left)

    #expect(rule.origin(ofDisplaySized: monitorSize, beside: home) == CGPoint(x: 0, y: -1692))
  }

  @Test func `a monitor above, centred, overhangs the screen equally on both sides`() {
    let rule = DisplayPlacement(display: monitor, position: .above, align: .center)

    #expect(rule.origin(ofDisplaySized: monitorSize, beside: home) == CGPoint(x: -604, y: -1692))
  }

  @Test func `a monitor above, right-aligned, lines up its right edge with the screen's`() {
    let rule = DisplayPlacement(display: monitor, position: .above, align: .right)

    #expect(rule.origin(ofDisplaySized: monitorSize, beside: home) == CGPoint(x: -1208, y: -1692))
  }

  @Test func `an iPad right of the screen, top-aligned, starts at its top-right corner`() {
    let rule = DisplayPlacement(display: .sidecar, position: .right, align: .top)

    #expect(rule.origin(ofDisplaySized: iPadSize, beside: home) == CGPoint(x: 1800, y: 0))
  }

  @Test func `a monitor below, centred, starts at the screen's bottom edge`() {
    let rule = DisplayPlacement(display: monitor, position: .below, align: .center)
    let size = CGSize(width: 2560, height: 1440)

    #expect(rule.origin(ofDisplaySized: size, beside: home) == CGPoint(x: -380, y: 1169))
  }

  @Test func `a monitor left of the screen, bottom-aligned, lines up the bottom edges`() {
    let rule = DisplayPlacement(display: monitor, position: .left, align: .bottom)
    let size = CGSize(width: 1920, height: 1080)

    #expect(rule.origin(ofDisplaySized: size, beside: home) == CGPoint(x: -1920, y: 89))
  }

  @Test func `a centred display half a point off is rounded down to a whole point`() {
    let rule = DisplayPlacement(display: monitor, position: .left, align: .center)
    let size = CGSize(width: 1920, height: 1080)

    #expect(rule.origin(ofDisplaySized: size, beside: home) == CGPoint(x: -1920, y: 44))
  }

  @Test func `placement follows the screen when it is not the main display`() {
    let rule = DisplayPlacement(display: monitor, position: .above, align: .left)
    let lowered = CGRect(x: 100, y: 1692, width: 1800, height: 1169)

    #expect(rule.origin(ofDisplaySized: monitorSize, beside: lowered) == CGPoint(x: 100, y: 0))
  }

  // MARK: Moves

  let rules = [
    DisplayPlacement(
      display: .monitor(vendor: 0x10ac, model: 41234, serial: 7), position: .above, align: .left),
    DisplayPlacement(display: .sidecar, position: .right, align: .top),
  ]

  func monitorAt(_ x: Double, _ y: Double, serial: UInt32 = 7) -> OnlineDisplay {
    OnlineDisplay(
      id: 2, vendor: 0x10ac, model: 41234, serial: serial,
      bounds: CGRect(x: x, y: y, width: 3008, height: 1692))
  }

  func iPadAt(_ x: Double, _ y: Double) -> OnlineDisplay {
    OnlineDisplay(
      id: 3, vendor: 0x6161_706C, model: 0x6950_6164, serial: 0,
      bounds: CGRect(x: x, y: y, width: 1366, height: 1024))
  }

  @Test func `nothing moves when every placed display is in place`() {
    let displays = [monitorAt(0, -1692), iPadAt(1800, 0)]

    #expect(DisplayPlacement.moves(placing: displays, beside: home, by: rules) == [])
  }

  @Test func `one display out of place moves every placed display together`() {
    let displays = [monitorAt(1800, 0), iPadAt(1800, 0)]

    #expect(
      DisplayPlacement.moves(placing: displays, beside: home, by: rules) == [
        DisplayMove(id: 2, origin: CGPoint(x: 0, y: -1692)),
        DisplayMove(id: 3, origin: CGPoint(x: 1800, y: 0)),
      ])
  }

  @Test func `a monitor with another serial number is left where it is`() {
    let displays = [monitorAt(1800, 0, serial: 8)]

    #expect(DisplayPlacement.moves(placing: displays, beside: home, by: rules) == [])
  }

  @Test func `the first rule that matches a display places it`() {
    let first = DisplayPlacement(display: .sidecar, position: .below, align: .left)

    #expect(
      DisplayPlacement.moves(placing: [iPadAt(1800, 0)], beside: home, by: [first] + rules) == [
        DisplayMove(id: 3, origin: CGPoint(x: 0, y: 1169))
      ])
  }
}
