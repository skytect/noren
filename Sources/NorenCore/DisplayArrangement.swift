// Where the displays go around the built-in screen, by the config's [[displays.place]] rules.
// Coordinates are global display coordinates, as CGDisplayBounds gives them: the main display's
// top-left corner at the origin, y growing down.
import CoreGraphics

/// A display that is online, as Quartz Display Services describes it.
public struct OnlineDisplay: Equatable, Sendable {
  public let id: UInt32
  /// CGDisplayVendorNumber, ModelNumber and SerialNumber.
  public let vendor: UInt32
  public let model: UInt32
  public let serial: UInt32
  public let bounds: CGRect

  public init(id: UInt32, vendor: UInt32, model: UInt32, serial: UInt32, bounds: CGRect) {
    self.id = id
    self.vendor = vendor
    self.model = model
    self.serial = serial
    self.bounds = bounds
  }
}

/// A display moved so its top-left corner is at `origin`.
public struct DisplayMove: Equatable, Sendable {
  public let id: UInt32
  public let origin: CGPoint

  public init(id: UInt32, origin: CGPoint) {
    self.id = id
    self.origin = origin
  }
}

extension DisplayPlacement {
  // Sidecar screens report vendor 'aapl' and model 'iPad'
  private static let sidecarVendor: UInt32 = 0x6161_706C
  private static let sidecarModel: UInt32 = 0x6950_6164

  /// Whether this rule is about `display`.
  public func matches(_ display: OnlineDisplay) -> Bool {
    switch self.display {
    case .monitor(let vendor, let model, let serial):
      display.vendor == vendor && display.model == model && display.serial == serial
    case .sidecar:
      display.vendor == Self.sidecarVendor && display.model == Self.sidecarModel
    }
  }

  /// Where a display of `size` goes by this rule, beside the built-in screen at `home`. A centred
  /// display is rounded down to a whole point, as displays sit only at whole points.
  public func origin(ofDisplaySized size: CGSize, beside home: CGRect) -> CGPoint {
    switch position {
    case .above:
      CGPoint(x: aligned(size.width, home.minX, home.maxX), y: home.minY - size.height)
    case .below:
      CGPoint(x: aligned(size.width, home.minX, home.maxX), y: home.maxY)
    case .left:
      CGPoint(x: home.minX - size.width, y: aligned(size.height, home.minY, home.maxY))
    case .right:
      CGPoint(x: home.maxX, y: aligned(size.height, home.minY, home.maxY))
    }
  }

  /// Where a `length` long edge starts when it lines up with the edge from `start` to `end`.
  private func aligned(_ length: Double, _ start: Double, _ end: Double) -> Double {
    switch align {
    case .left, .top: start
    case .right, .bottom: end - length
    case .center: start + ((end - start - length) / 2).rounded(.down)
    }
  }

  /// The moves that put `displays` where `rules` say, beside the built-in screen at `home`: each
  /// display takes the first rule that matches it, and one no rule matches stays. Empty when every
  /// display is in place already, so the move's own reconfiguration does not move them again;
  /// otherwise every display a rule places, so they move together in one configuration.
  public static func moves(
    placing displays: [OnlineDisplay], beside home: CGRect, by rules: [DisplayPlacement]
  ) -> [DisplayMove] {
    var moves: [DisplayMove] = []
    var inPlace = true
    for display in displays {
      guard let rule = rules.first(where: { $0.matches(display) }) else { continue }
      let origin = rule.origin(ofDisplaySized: display.bounds.size, beside: home)
      if origin != display.bounds.origin { inPlace = false }
      moves.append(DisplayMove(id: display.id, origin: origin))
    }
    return inPlace ? [] : moves
  }
}
