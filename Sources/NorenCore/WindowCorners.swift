// A model of how macOS 27 rounds a window's corners, for the border to follow.
//
// The window server knows the radius of the windows it rounds alike at all four corners, and that
// one is taken as it is. It reports 0 for the rest: windows that draw their own frame (Ghostty,
// Chromium), and windows whose corners AppKit has made differ. Those get the radius AppKit gives a
// standard titled window, with AppKit's rule for corners near the screen's applied:
//
// Since macOS 26 a window's bottom corner near the same rounded corner of its screen follows the
// screen's. With R the screen's radius (37 points on a 14-inch MacBook Pro's built-in screen, 0 on
// a square monitor) and d the larger of the corner's horizontal and vertical distance from the
// screen's corner, the window's radius r becomes r + (R - r)(1 - d / R) while d < R: R at the
// screen's corner, r from R away. Top corners keep r, even at the screen's top corners. Found on
// macOS 27.2 by moving a test window about a built-in screen and reading AppKit's private
// _cornerRadii for it; the window server reported 0 for each enlarged one, and a window given
// another radius of its own was never enlarged.
import CoreGraphics

/// A window's corner radii in points, by where the corners are on screen.
public struct WindowCorners: Equatable, Sendable {
  public var topLeft: CGFloat
  public var topRight: CGFloat
  public var bottomLeft: CGFloat
  public var bottomRight: CGFloat

  public init(topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) {
    self.topLeft = topLeft
    self.topRight = topRight
    self.bottomLeft = bottomLeft
    self.bottomRight = bottomRight
  }

  /// All four corners rounded alike, as the window server rounds the windows it knows the radius
  /// of.
  public init(all radius: CGFloat) {
    self.init(topLeft: radius, topRight: radius, bottomLeft: radius, bottomRight: radius)
  }

  /// The corners AppKit gives a window at `frame` whose own radius is `radius`, on the screen at
  /// `screen` whose corners have the radius `screenRadius`. Both frames are in Cocoa coordinates,
  /// where y grows upwards, so the bottom is the smaller y.
  public init(frame: CGRect, radius: CGFloat, screen: CGRect, screenRadius: CGFloat) {
    func followingScreen(_ corner: CGPoint, _ screenCorner: CGPoint) -> CGFloat {
      guard screenRadius > radius else { return radius }
      let distance = max(abs(corner.x - screenCorner.x), abs(corner.y - screenCorner.y))
      guard distance < screenRadius else { return radius }
      return radius + (screenRadius - radius) * (1 - distance / screenRadius)
    }
    self.init(
      topLeft: radius,
      topRight: radius,
      bottomLeft: followingScreen(
        CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: screen.minX, y: screen.minY)),
      bottomRight: followingScreen(
        CGPoint(x: frame.maxX, y: frame.minY), CGPoint(x: screen.maxX, y: screen.minY)))
  }
}

extension CGRect {
  /// The index of the rect in `rects` this one overlaps most, as AppKit picks a window's screen;
  /// nil when it overlaps none.
  public func indexOfLargestOverlap(in rects: [CGRect]) -> Int? {
    var best: (index: Int, area: CGFloat)?
    for (index, rect) in rects.enumerated() {
      let overlap = intersection(rect)
      let area = overlap.isNull ? 0 : overlap.width * overlap.height
      if area > (best?.area ?? 0) { best = (index, area) }
    }
    return best?.index
  }
}
