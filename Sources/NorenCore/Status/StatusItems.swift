// The bar's status items, worked out from what macOS last said: the microphone and the camera
// while something uses them, Tailscale, Ethernet, Wi-Fi, the output volume and the battery, left
// to right. Each is an SF Symbol, with a level and text when it has them.

/// How a status item is inked; the bar picks the colours.
public enum StatusTone: Equatable, Sendable {
  case normal
  /// Off.
  case dim
  /// Needs a look: a low battery, Wi-Fi without a network.
  case warn
  /// In use, as macOS's own orange dot.
  case microphone
  /// In use, as macOS's own green dot.
  case camera
}

/// What a click on a status item does.
public enum StatusAction: Equatable, Sendable {
  /// Opens `url`, such as a System Settings pane.
  case open(url: String)
  /// Opens the app `bundleId`.
  case launch(bundleId: String)
}

/// One of the bar's status items.
public struct StatusItem: Equatable, Sendable {
  public let symbol: String
  /// The symbol's variable value, from 0 to 1; nil for none.
  public let level: Double?
  public let tone: StatusTone
  /// Drawn after the symbol.
  public let text: String?
  public let action: StatusAction?

  public init(
    symbol: String, level: Double? = nil, tone: StatusTone = .normal, text: String? = nil,
    action: StatusAction? = nil
  ) {
    self.symbol = symbol
    self.level = level
    self.tone = tone
    self.text = text
    self.action = action
  }

  /// Whether the two draw alike: levels closer than half a percent look the same.
  public func looksLike(_ other: StatusItem) -> Bool {
    let sameLevel =
      switch (level, other.level) {
      case (nil, nil): true
      case (let a?, let b?): abs(a - b) < 0.005
      default: false
      }
    return symbol == other.symbol && tone == other.tone && text == other.text && sameLevel
  }
}

/// What Wi-Fi is doing.
public enum WiFiState: Equatable, Sendable {
  /// There is no Wi-Fi interface.
  case none
  case off
  /// On, without a network.
  case disconnected
  case connected

  /// The state of a Wi-Fi interface whose power is `power` (nil when macOS does not say), whose
  /// link is up with an IPv4 address (`isUp`), and which macOS has any state for (`isKnown`).
  public init(power: Bool?, isUp: Bool, isKnown: Bool) {
    if power == false {
      self = .off
    } else if isUp {
      self = .connected
    } else if isKnown {
      self = .disconnected
    } else {
      self = .none
    }
  }
}

/// What the status items show, as last read from macOS.
public struct StatusReadings: Equatable, Sendable {
  /// What a click opens.
  public static let batterySettings =
    "x-apple.systempreferences:com.apple.Battery-Settings.extension"
  public static let soundSettings = "x-apple.systempreferences:com.apple.Sound-Settings.extension"
  public static let wiFiSettings = "x-apple.systempreferences:com.apple.wifi-settings-extension"
  public static let networkSettings =
    "x-apple.systempreferences:com.apple.Network-Settings.extension"

  /// The default output device.
  public struct Output: Equatable, Sendable {
    /// From 0 to 1; nil for a device without a volume control.
    public var volume: Double?
    public var muted: Bool

    public init(volume: Double?, muted: Bool) {
      self.volume = volume
      self.muted = muted
    }
  }

  /// The internal battery.
  public struct Battery: Equatable, Sendable {
    public var percent: Int
    public var onPower: Bool

    public init(percent: Int, onPower: Bool) {
      self.percent = percent
      self.onPower = onPower
    }

    /// The percentage of a battery holding `current` of `max` (IOKit's capacities); `current`
    /// itself when `max` is not positive, as some batteries report percentages directly.
    public static func percent(current: Int, max: Int) -> Int {
      max > 0 ? Int((100 * Double(current) / Double(max)).rounded()) : current
    }
  }

  public var microphone = false
  public var camera = false
  /// The installed Tailscale app's bundle id; nil when it is not installed.
  public var tailscaleApp: String?
  public var tailscaleConnected = false
  /// On Ethernet.
  public var wired = false
  public var wiFi = WiFiState.none
  /// nil when there is no default output device.
  public var output: Output?
  /// nil when there is no internal battery.
  public var battery: Battery?

  public init() {}

  /// The items, left to right.
  public var items: [StatusItem] {
    var items: [StatusItem] = []
    if microphone { items.append(StatusItem(symbol: "mic.fill", tone: .microphone)) }
    if camera { items.append(StatusItem(symbol: "video.fill", tone: .camera)) }
    if let tailscaleApp {
      // Tailscale's own logo is a grid of dots: filled while connected
      items.append(
        StatusItem(
          symbol: tailscaleConnected ? "circle.grid.3x3.fill" : "circle.grid.3x3",
          tone: tailscaleConnected ? .normal : .dim, action: .launch(bundleId: tailscaleApp)))
    }
    if wired {
      items.append(StatusItem(symbol: "cable.connector", action: .open(url: Self.networkSettings)))
    }
    // On Ethernet, Wi-Fi shows only while connected
    switch wiFi {
    case .connected:
      items.append(StatusItem(symbol: "wifi", action: .open(url: Self.wiFiSettings)))
    case .disconnected where !wired:
      items.append(
        StatusItem(
          symbol: "wifi.exclamationmark", tone: .warn, action: .open(url: Self.wiFiSettings)))
    case .off where !wired:
      items.append(
        StatusItem(symbol: "wifi.slash", tone: .dim, action: .open(url: Self.wiFiSettings)))
    default:
      break
    }
    if let output {
      let silent = output.muted || output.volume == 0
      items.append(
        StatusItem(
          symbol: silent ? "speaker.slash.fill" : "speaker.wave.3.fill",
          level: silent ? nil : output.volume, tone: silent ? .dim : .normal,
          action: .open(url: Self.soundSettings)))
    }
    if let battery {
      items.append(
        StatusItem(
          symbol: Self.batterySymbol(battery),
          tone: !battery.onPower && battery.percent <= 20 ? .warn : .normal,
          text: "\(battery.percent)%", action: .open(url: Self.batterySettings)))
    }
    return items
  }

  private static func batterySymbol(_ battery: Battery) -> String {
    if battery.onPower { return "battery.100percent.bolt" }
    return switch battery.percent {
    case 88...: "battery.100percent"
    case 63...: "battery.75percent"
    case 38...: "battery.50percent"
    case 13...: "battery.25percent"
    default: "battery.0percent"
    }
  }
}

extension [StatusItem] {
  /// Whether the two rows draw alike, item by item.
  public func looksLike(_ other: [StatusItem]) -> Bool {
    count == other.count && zip(self, other).allSatisfy { $0.looksLike($1) }
  }
}

/// Tailscale's addresses: the shared address space 100.64.0.0/10.
public enum Tailnet {
  /// Whether `address`, dotted-decimal IPv4, is a tailnet address.
  public static func contains(_ address: String) -> Bool {
    let parts = address.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return false }
    var value: UInt32 = 0
    for part in parts {
      guard part.allSatisfy({ $0.isASCII && $0.isNumber }), let byte = UInt8(part) else {
        return false
      }
      value = value << 8 | UInt32(byte)
    }
    return value & 0xffc0_0000 == 0x6440_0000
  }
}
