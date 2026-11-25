// The workspace chips' sizes. A chip holds the workspace's name, the icons of its apps, and "+N"
// for the apps whose icons did not fit. Every chip shows the same number of icons at most: as
// many as let the whole row fit, up to `maxIcons`.

/// The sizes of a row of workspace chips, in points.
public struct ChipLayout: Equatable, Sendable {
  public static let height = 22.0
  /// Inside a chip, on either side of what it holds.
  public static let padding = 7.0
  /// Between chips.
  public static let gap = 4.0
  public static let iconSize = 16.0
  public static let iconGap = 2.0
  /// Between a chip's name and its first icon.
  public static let labelIconGap = 5.0
  public static let maxIcons = 4

  /// What one chip holds.
  public struct Chip: Equatable, Sendable {
    /// The name's width, rounded up to a whole point.
    public let labelWidth: Double
    /// How many of its apps have icons.
    public let iconCount: Int

    public init(labelWidth: Double, iconCount: Int) {
      self.labelWidth = labelWidth
      self.iconCount = iconCount
    }
  }

  /// The icons every chip shows at most.
  public let iconLimit: Int
  /// Each chip's width.
  public let widths: [Double]

  /// The layout of `chips` in `room` points: the most icons per chip, up to `maxIcons`, that let
  /// the row fit, or none when even that does not. `moreWidth(n)` is the width of the label
  /// "+n", rounded up.
  public init(chips: [Chip], room: Double, moreWidth: (Int) -> Double) {
    var limit = Self.maxIcons
    while true {
      let widths = chips.map { chip in
        let shown = min(chip.iconCount, limit)
        let content = Self.contentWidth(
          labelWidth: chip.labelWidth, icons: shown, hidden: chip.iconCount - shown,
          moreWidth: moreWidth)
        return max(Self.height, content + 2 * Self.padding)
      }
      let total = widths.reduce(0, +) + Double(max(0, widths.count - 1)) * Self.gap
      if limit == 0 || total <= room {
        iconLimit = limit
        self.widths = widths
        return
      }
      limit -= 1
    }
  }

  /// The width of a chip's contents: its name, `icons` icons, and "+`hidden`" when it shows
  /// some icons but not all.
  public static func contentWidth(
    labelWidth: Double, icons: Int, hidden: Int, moreWidth: (Int) -> Double
  ) -> Double {
    var width = labelWidth
    if icons > 0 {
      width += labelIconGap + Double(icons) * iconSize + Double(icons - 1) * iconGap
      if hidden > 0 { width += iconGap + moreWidth(hidden) }
    }
    return width
  }
}
