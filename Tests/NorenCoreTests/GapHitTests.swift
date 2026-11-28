import CoreGraphics
import NorenCore
import Testing

@Suite struct GapHitTests {
  /// Two windows side by side with a 12 point gap between x 900 and 912
  let sideBySide = [
    GapHit.Tile(id: 1, frame: CGRect(x: 0, y: 60, width: 900, height: 1000)),
    GapHit.Tile(id: 2, frame: CGRect(x: 912, y: 60, width: 888, height: 1000)),
  ]

  /// Left column split top and bottom (gap between y 500 and 512), one window on the right
  let column = [
    GapHit.Tile(id: 1, frame: CGRect(x: 0, y: 60, width: 900, height: 440)),
    GapHit.Tile(id: 3, frame: CGRect(x: 0, y: 512, width: 900, height: 548)),
    GapHit.Tile(id: 2, frame: CGRect(x: 912, y: 60, width: 888, height: 1000)),
  ]

  @Test func `a press between two windows side by side resizes the left one's width`() {
    #expect(GapHit(at: CGPoint(x: 906, y: 400), among: sideBySide)?.width == 1)
    #expect(GapHit(at: CGPoint(x: 906, y: 400), among: sideBySide)?.height == nil)
  }

  @Test func `a press between stacked windows resizes the top one's height`() {
    let hit = GapHit(at: CGPoint(x: 400, y: 506), among: column)

    #expect(hit?.height == 1)
    #expect(hit?.width == nil)
  }

  @Test func `a press where gaps cross resizes both ways`() {
    let hit = GapHit(at: CGPoint(x: 906, y: 506), among: column)

    #expect(hit?.width == 1)
    #expect(hit?.height == 1)
  }

  @Test func `a press in a window is no gap`() {
    #expect(GapHit(at: CGPoint(x: 400, y: 400), among: sideBySide) == nil)
  }

  @Test func `a press past the last window, at the screen's edge, is no gap`() {
    let one = [GapHit.Tile(id: 1, frame: CGRect(x: 0, y: 60, width: 1790, height: 1000))]

    #expect(GapHit(at: CGPoint(x: 1795, y: 400), among: one) == nil)
  }

  @Test func `windows further apart than a gap are not resized`() {
    let apart = [
      GapHit.Tile(id: 1, frame: CGRect(x: 0, y: 60, width: 400, height: 1000)),
      GapHit.Tile(id: 2, frame: CGRect(x: 1000, y: 60, width: 800, height: 1000)),
    ]

    #expect(GapHit(at: CGPoint(x: 700, y: 400), among: apart) == nil)
  }
}
