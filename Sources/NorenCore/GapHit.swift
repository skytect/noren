// A press in the gap between tiled windows resizes them, as Hyprland's resize_on_border does: the
// gap is no window's, so macOS gives it to the desktop. A gap counts where a window ends on one
// side of the point and another begins on the other, no further apart than `reach`; it is found
// from the windows' frames, so it follows AeroSpace's gaps whatever they are. Where gaps cross, the
// press resizes both ways.
import CoreGraphics

/// The windows a press in a gap resizes: the one whose right edge, and the one whose bottom edge,
/// the gap runs along.
public struct GapHit: Equatable, Sendable {
  /// A tiled window on screen: AeroSpace's id of it, and its frame in the window server's
  /// coordinates (y down)
  public struct Tile: Equatable, Sendable {
    public let id: UInt32
    public let frame: CGRect

    public init(id: UInt32, frame: CGRect) {
      self.id = id
      self.frame = frame
    }
  }

  /// The widest gap counted, in points
  public static let reach: CGFloat = 40

  /// The window left of a vertical gap, whose width the press changes
  public let width: UInt32?
  /// The window above a horizontal gap, whose height the press changes
  public let height: UInt32?

  /// The gap at `point` among `tiles`, nil when the point is in a window or in no gap.
  public init?(at point: CGPoint, among tiles: [Tile]) {
    guard !tiles.contains(where: { $0.frame.contains(point) }) else { return nil }
    let reach = Self.reach
    // Alongside a window: within its span, give or take a gap, so a crossing counts on both sides
    func beside(_ low: CGFloat, _ high: CGFloat, _ value: CGFloat) -> Bool {
      value >= low - reach && value <= high + reach
    }
    // Of the windows along a gap, the one nearest the point along it, then the lower id: at a
    // crossing both windows on that side share the edge
    func nearest(_ candidates: [Tile], along: (CGRect) -> (CGFloat, CGFloat), at value: CGFloat)
      -> Tile?
    {
      func distance(_ tile: Tile) -> CGFloat {
        let (low, high) = along(tile.frame)
        return max(low - value, value - high, 0)
      }
      return candidates.min { (distance($0), $0.id) < (distance($1), $1.id) }
    }
    let left = nearest(
      tiles.filter {
        point.x >= $0.frame.maxX && point.x - $0.frame.maxX <= reach
          && beside($0.frame.minY, $0.frame.maxY, point.y)
      }, along: { ($0.minY, $0.maxY) }, at: point.y)
    let right = tiles.contains {
      $0.frame.minX >= point.x && $0.frame.minX - point.x <= reach
        && beside($0.frame.minY, $0.frame.maxY, point.y)
    }
    let above = nearest(
      tiles.filter {
        point.y >= $0.frame.maxY && point.y - $0.frame.maxY <= reach
          && beside($0.frame.minX, $0.frame.maxX, point.x)
      }, along: { ($0.minX, $0.maxX) }, at: point.x)
    let below = tiles.contains {
      $0.frame.minY >= point.y && $0.frame.minY - point.y <= reach
        && beside($0.frame.minX, $0.frame.maxX, point.x)
    }
    width = right ? left?.id : nil
    height = below ? above?.id : nil
    guard width != nil || height != nil else { return nil }
  }
}
