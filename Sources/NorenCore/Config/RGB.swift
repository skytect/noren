/// An sRGB colour, written in the config as `"RRGGBB"` or `"#RRGGBB"`.
public struct RGB: Equatable, Sendable {
  /// From 0 to 1.
  public let red: Double
  public let green: Double
  public let blue: Double

  public init(red: Double, green: Double, blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  /// The colour `hex` spells, or nil if it is not six hex digits after an optional `#`.
  public init?(hex: String) {
    let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
    guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = Int(digits, radix: 16)
    else { return nil }
    red = Double((value >> 16) & 0xff) / 255
    green = Double((value >> 8) & 0xff) / 255
    blue = Double(value & 0xff) / 255
  }
}

extension RGB: Decodable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    guard let colour = RGB(hex: try container.decode(String.self)) else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "expected a colour as \"RRGGBB\"")
    }
    self = colour
  }
}
