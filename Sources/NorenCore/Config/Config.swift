// noren's settings, as read from its TOML file (docs/configuration.md). Every key may be left out:
// a missing key takes the default written here, or, where the default is nil, a value the part
// works out itself (the bar's height from the menu bar, the floating apps from AeroSpace's own
// config). A key noren does not know is an error, so a typo is not silently ignored.

/// All of noren's settings.
public struct Config: Equatable, Sendable {
  public var bar = BarConfig()
  public var status = PartConfig()
  public var strip = PartConfig()
  public var stay = StayConfig()
  public var pointer = PartConfig()
  public var border = BorderConfig()
  public var drag = DragConfig()
  public var dwindle = PartConfig()
  public var appear = AppearConfig()
  public var displays = DisplaysConfig()
  public var restore = PartConfig()
  public var layers = PartConfig()
  public var cursors = PartConfig()
  public var focusRules: [FocusRule] = []

  public init() {}
}

/// Moving a window by dragging anywhere in it with a key held.
public struct DragConfig: Equatable, Sendable {
  /// The key held
  public enum Modifier: String, Equatable, Sendable {
    case alt, ctrl, cmd
  }

  public var enable = true
  public var modifier = Modifier.alt

  public init() {}
}

/// A part with nothing to set but whether it runs.
public struct PartConfig: Equatable, Sendable {
  public var enable = true

  public init() {}
}

/// The bar over the menu bar.
public struct BarConfig: Equatable, Sendable {
  public var enable = true
  /// In points, the least on any screen; nil for each screen's own menu bar height.
  public var height: Double?
  public var accent: RGB?
  public var text: RGB?
  public var dim: RGB?
  public var warn: RGB?
  public var base: RGB?
  /// The key code the clock presses to open Notification Center; nil for the shortcut macOS has
  /// for it in its keyboard settings.
  public var notificationCenterKey: Int?

  public init() {}
}

/// Staying on a workspace whose last window closed.
public struct StayConfig: Equatable, Sendable {
  public var enable = true
  /// The AeroSpace bindings that close a window; nil for those AeroSpace's config binds to
  /// `close`.
  public var closeBindings: [String]?

  public init() {}
}

/// The focused window's border.
public struct BorderConfig: Equatable, Sendable {
  public var enable = true
  /// In points.
  public var width = 2.0
  public var opacity = 1.0
  /// nil for the system's accent colour.
  public var color: RGB?
  /// The colour at the bottom-right corner, blended from `color` at the top-left; nil for `color`.
  public var colorEnd: RGB?

  public init() {}
}

/// New windows shown only once in place.
public struct AppearConfig: Equatable, Sendable {
  public var enable = true
  /// Apps whose windows float, so are never hidden while placed; nil for the apps AeroSpace's
  /// config floats by app id alone.
  public var floatingApps: [String]?

  public init() {}
}

/// Where the screens sit, and what they show.
public struct DisplaysConfig: Equatable, Sendable {
  public var enable = true
  /// An image put on every screen, now and whenever screens change; nil to leave them be.
  public var wallpaper: String?
  public var place: [DisplayPlacement] = []

  public init() {}
}

/// Where one display is kept, relative to the built-in screen.
public struct DisplayPlacement: Equatable, Sendable {
  public enum Display: Equatable, Sendable {
    /// A monitor, by the numbers CGDisplayVendorNumber, ModelNumber and SerialNumber give.
    case monitor(vendor: UInt32, model: UInt32, serial: UInt32)
    /// An iPad used as a screen.
    case sidecar
  }

  public enum Position: String, Equatable, Sendable {
    case above, below, left, right
  }

  /// Which edges line up: left, right or center beside `above` and `below`; top, bottom or
  /// center beside `left` and `right`.
  public enum Alignment: String, Equatable, Sendable {
    case left, right, top, bottom, center
  }

  public var display: Display
  public var position: Position
  public var align: Alignment

  public init(display: Display, position: Position, align: Alignment) {
    self.display = display
    self.position = position
    self.align = align
  }
}

/// Commands run as focus moves into and out of matching windows.
public struct FocusRule: Equatable, Sendable {
  /// The app's bundle id; nil for any app.
  public var appId: String?
  /// A regular expression the window's title must contain a match of; nil for any title.
  public var titleRegex: String?
  /// Run, in order, when focus moves into a matching window from one that is not.
  public var enter: [[String]]
  /// Run, in order, when focus moves out of a matching window to one that is not.
  public var leave: [[String]]

  public init(appId: String?, titleRegex: String?, enter: [[String]], leave: [[String]]) {
    self.appId = appId
    self.titleRegex = titleRegex
    self.enter = enter
    self.leave = leave
  }
}
