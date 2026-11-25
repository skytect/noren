/// A display mode, as CGDisplayMode describes it.
public struct DisplayMode: Equatable, Sendable {
  /// In points: the size Displays settings calls "Looks like".
  public let width: Int
  public let height: Int
  public let pixelWidth: Int
  public let pixelHeight: Int
  public let refreshRate: Double

  public init(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double) {
    self.width = width
    self.height = height
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.refreshRate = refreshRate
  }

  /// The best of `modes` for each size, smallest first: the sharpest (most pixels), then the
  /// highest refresh rate.
  public static func bestForEachSize(of modes: [DisplayMode]) -> [DisplayMode] {
    Dictionary(grouping: modes) { [$0.width, $0.height] }.values
      .compactMap { $0.max(by: { $1.isBetter(than: $0) }) }
      .sorted { ($0.width, $0.height) < ($1.width, $1.height) }
  }

  /// The best of `modes` that is `width` by `height` points, or nil if none is.
  public static func best(width: Int, height: Int, of modes: [DisplayMode]) -> DisplayMode? {
    bestForEachSize(of: modes).first { $0.width == width && $0.height == height }
  }

  private func isBetter(than other: DisplayMode) -> Bool {
    if pixelWidth != other.pixelWidth { return pixelWidth > other.pixelWidth }
    return refreshRate > other.refreshRate
  }
}
