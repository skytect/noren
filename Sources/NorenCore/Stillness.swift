// When the windows under appear's cover have stopped moving. The windows that make room for a new
// one may still be on their way when it is shown, so the cover waits for them to settle.
import CoreGraphics

/// A window on screen and where it is, as the window server lists it.
public struct WindowFrame: Equatable, Sendable {
  public let window: UInt32
  public let bounds: CGRect

  public init(window: UInt32, bounds: CGRect) {
    self.window = window
    self.bounds = bounds
  }
}

/// Looks taken at the windows on a screen, one after another: they count as still once their
/// frames, in front-to-back order, have come back unchanged `checks` times in a row.
public struct Stillness: Sendable {
  /// How many unchanged looks in a row make the windows still
  public static let checks = 5

  private var last: [WindowFrame]?
  private var unchanged = 0

  public init() {}

  /// Takes the look `frames`, and returns whether the windows are now still.
  public mutating func look(_ frames: [WindowFrame]) -> Bool {
    unchanged = frames == last ? unchanged + 1 : 0
    last = frames
    return unchanged >= Self.checks
  }
}
