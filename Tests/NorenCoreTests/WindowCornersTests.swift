import CoreGraphics
import NorenCore
import Testing

/// A 14-inch MacBook Pro's built-in screen (radius 37) and a standard window's radius, 16.
@Suite struct WindowCornersTests {
  let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

  @Test func `a window flush in the screen's bottom-left corner takes the screen's radius there`() {
    let corners = WindowCorners(
      frame: CGRect(x: 0, y: 0, width: 500, height: 400), radius: 16, screen: screen,
      screenRadius: 37)

    #expect(corners == WindowCorners(topLeft: 16, topRight: 16, bottomLeft: 37, bottomRight: 16))
  }

  @Test func `a window flush in the screen's bottom-right corner takes the screen's radius there`()
  {
    let corners = WindowCorners(
      frame: CGRect(x: 1012, y: 0, width: 500, height: 400), radius: 16, screen: screen,
      screenRadius: 37)

    #expect(corners == WindowCorners(topLeft: 16, topRight: 16, bottomLeft: 16, bottomRight: 37))
  }

  @Test func `a bottom corner 10 points from the screen's corner is rounded part of the way`() {
    // d = max(10, 4) = 10: 16 + 21 * (1 - 10/37) = 16 + 567/37 = 31.3243...
    let corners = WindowCorners(
      frame: CGRect(x: 10, y: 4, width: 500, height: 400), radius: 16, screen: screen,
      screenRadius: 37)

    #expect(abs(corners.bottomLeft - 31.3243) < 0.0001)
    #expect(corners.bottomRight == 16)
  }

  @Test func `a bottom corner 40 points from the screen's corner keeps the window's radius`() {
    let corners = WindowCorners(
      frame: CGRect(x: 40, y: 0, width: 500, height: 400), radius: 16, screen: screen,
      screenRadius: 37)

    #expect(corners == WindowCorners(all: 16))
  }

  @Test func `a window flush in the screen's top-left corner keeps the window's radius on top`() {
    let corners = WindowCorners(
      frame: CGRect(x: 0, y: 582, width: 500, height: 400), radius: 16, screen: screen,
      screenRadius: 37)

    #expect(corners == WindowCorners(all: 16))
  }

  @Test func `a window in the corner of a square screen keeps its own radius`() {
    let corners = WindowCorners(
      frame: CGRect(x: 0, y: 0, width: 500, height: 400), radius: 16, screen: screen,
      screenRadius: 0)

    #expect(corners == WindowCorners(all: 16))
  }

  @Test func `the distance is measured from the window's own screen, wherever it sits`() {
    // A screen right of the built-in one and lower: d = 5, 16 + 21 * 32/37 = 34.1621...
    let corners = WindowCorners(
      frame: CGRect(x: 1517, y: -200, width: 800, height: 600), radius: 16,
      screen: CGRect(x: 1512, y: -200, width: 1920, height: 1080), screenRadius: 37)

    #expect(abs(corners.bottomLeft - 34.1622) < 0.0001)
  }

  @Test func `a window rounder than the screen keeps its own radius in the screen's corner`() {
    let corners = WindowCorners(
      frame: CGRect(x: 0, y: 0, width: 500, height: 400), radius: 40, screen: screen,
      screenRadius: 37)

    #expect(corners == WindowCorners(all: 40))
  }

  @Test func `a window's screen is the one it overlaps most`() {
    let screens = [screen, CGRect(x: 1512, y: 0, width: 1920, height: 1080)]
    let window = CGRect(x: 1400, y: 100, width: 600, height: 400)

    #expect(window.indexOfLargestOverlap(in: screens) == 1)
  }

  @Test func `a window off every screen has none`() {
    let window = CGRect(x: -3000, y: 100, width: 600, height: 400)

    #expect(window.indexOfLargestOverlap(in: [screen]) == nil)
  }
}
