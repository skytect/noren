// Resize keys that move an edge the way the arrow points. AeroSpace's `resize width +N` grows the
// focused window whichever side it is on, so on a right-hand window "wider" moves the divider left,
// against the arrow. Here the arrow moves the divider: towards a neighbour on that side the focused
// window grows, with none there it gives up room on the other side.
import CoreGraphics

/// An arrow of the resize keys.
public enum ResizeArrow: String, Sendable, CaseIterable {
  case left, right, up, down
}

/// The AeroSpace resize an arrow comes to for the focused window.
public struct EdgeResize: Equatable, Sendable {
  public enum Dimension: String, Sendable {
    case width, height
  }

  public let dimension: Dimension
  /// In points: more than 0 grows the window, less than 0 shrinks it
  public let points: Int

  /// The resize for `arrow` by `points` of the window at `focused` among the other tiled windows
  /// of its workspace, at `others` (frames in the window server's coordinates, y down)
  public init(_ arrow: ResizeArrow, by points: Int, focused: CGRect, others: [CGRect]) {
    // Within a gap of the focused window's edge and alongside it
    let gap: CGFloat = 40
    func alongside(_ low: CGFloat, _ high: CGFloat, _ otherLow: CGFloat, _ otherHigh: CGFloat)
      -> Bool
    { min(high, otherHigh) > max(low, otherLow) }
    let neighbour =
      switch arrow {
      case .left:
        others.contains {
          $0.maxX <= focused.minX + 1 && focused.minX - $0.maxX <= gap
            && alongside(focused.minY, focused.maxY, $0.minY, $0.maxY)
        }
      case .right:
        others.contains {
          $0.minX >= focused.maxX - 1 && $0.minX - focused.maxX <= gap
            && alongside(focused.minY, focused.maxY, $0.minY, $0.maxY)
        }
      case .up:
        others.contains {
          $0.maxY <= focused.minY + 1 && focused.minY - $0.maxY <= gap
            && alongside(focused.minX, focused.maxX, $0.minX, $0.maxX)
        }
      case .down:
        others.contains {
          $0.minY >= focused.maxY - 1 && $0.minY - focused.maxY <= gap
            && alongside(focused.minX, focused.maxX, $0.minX, $0.maxX)
        }
      }
    dimension = arrow == .left || arrow == .right ? .width : .height
    self.points = neighbour ? points : -points
  }

  /// The AeroSpace command's arguments
  public var arguments: [String] {
    ["resize", dimension.rawValue, points > 0 ? "+\(points)" : "\(points)"]
  }
}
