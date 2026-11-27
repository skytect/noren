// Reading Config from TOML. Keys are kebab-case in the file (`notification-center-key`) and
// camelCase in Swift; every table rejects keys it does not know, and every mistake is reported
// with where it is.
import Foundation
import TOMLDecoder

/// What is wrong with a config file, in words for the person who wrote it.
public struct ConfigError: Error, Equatable, CustomStringConvertible {
  public let description: String

  public init(_ description: String) {
    self.description = description
  }
}

extension Config {
  /// The config `text` holds.
  public init(toml text: String) throws(ConfigError) {
    do {
      self = try TOMLDecoder(strategy: .init(key: .custom(camelCase))).decode(
        Config.self, from: text)
    } catch let error as UnknownKey {
      throw ConfigError("\(error.location): unknown key")
    } catch let error as TOMLError {
      throw ConfigError(error.description)
    } catch let error as DecodingError {
      throw ConfigError(describe(error))
    } catch {
      throw ConfigError(String(describing: error))
    }
  }
}

extension Config: Decodable {
  enum CodingKeys: String, CodingKey, CaseIterable {
    case bar, status, strip, stay, pointer, border, drag, dwindle, appear, displays, restore, layers
    case aerospace
    case focusRules = "focusRule"
  }

  public init(from decoder: any Decoder) throws {
    try rejectUnknownKeys(decoder, CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    bar = try container.value(.bar, default: bar)
    status = try container.value(.status, default: status)
    strip = try container.value(.strip, default: strip)
    stay = try container.value(.stay, default: stay)
    pointer = try container.value(.pointer, default: pointer)
    border = try container.value(.border, default: border)
    drag = try container.value(.drag, default: drag)
    dwindle = try container.value(.dwindle, default: dwindle)
    appear = try container.value(.appear, default: appear)
    displays = try container.value(.displays, default: displays)
    restore = try container.value(.restore, default: restore)
    layers = try container.value(.layers, default: layers)
    focusRules = try container.value(.focusRules, default: focusRules)
    aerospace = try container.value(.aerospace, default: aerospace)
  }
}

extension AeroSpaceAgentConfig: Decodable {
  enum CodingKeys: String, CodingKey, CaseIterable {
    case start
  }

  public init(from decoder: any Decoder) throws {
    try rejectUnknownKeys(decoder, CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    start = try container.value(.start, default: start)
  }
}

extension DragConfig: Decodable {
  enum CodingKeys: String, CodingKey, CaseIterable {
    case enable, modifier
  }

  public init(from decoder: any Decoder) throws {
    try rejectUnknownKeys(decoder, CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    enable = try container.value(.enable, default: enable)
    modifier = try container.value(.modifier, default: modifier)
  }
}

extension DragConfig.Modifier: Decodable {}

extension PartConfig: Decodable {
  enum CodingKeys: String, CodingKey, CaseIterable {
    case enable
  }

  public init(from decoder: any Decoder) throws {
    try rejectUnknownKeys(decoder, CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    enable = try container.value(.enable, default: enable)
  }
}

extension BarConfig: Decodable {
  enum CodingKeys: String, CodingKey, CaseIterable {
    case enable, height, accent, text, dim, warn, base, notificationCenterKey
  }

  public init(from decoder: any Decoder) throws {
    try rejectUnknownKeys(decoder, CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    enable = try container.value(.enable, default: enable)
    height = try container.optional(Double.self, .height)
    accent = try container.optional(RGB.self, .accent)
    text = try container.optional(RGB.self, .text)
    dim = try container.optional(RGB.self, .dim)
    warn = try container.optional(RGB.self, .warn)
    base = try container.optional(RGB.self, .base)
    notificationCenterKey = try container.optional(Int.self, .notificationCenterKey)
    if let height, height <= 0 {
      throw DecodingError.dataCorruptedError(
        forKey: .height, in: container, debugDescription: "must be more than 0")
    }
    // macOS's virtual key codes, as CGKeyCode holds them
    if let notificationCenterKey, !(0...0x7f).contains(notificationCenterKey) {
      throw DecodingError.dataCorruptedError(
        forKey: .notificationCenterKey, in: container,
        debugDescription: "must be a key code, from 0 to 127")
    }
  }
}

extension StayConfig: Decodable {
  enum CodingKeys: String, CodingKey, CaseIterable {
    case enable, closeBindings
  }

  public init(from decoder: any Decoder) throws {
    try rejectUnknownKeys(decoder, CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    enable = try container.value(.enable, default: enable)
    closeBindings = try container.optional([String].self, .closeBindings)
  }
}

extension BorderConfig: Decodable {
  enum CodingKeys: String, CodingKey, CaseIterable {
    case enable, width, opacity, color, colorEnd
  }

  public init(from decoder: any Decoder) throws {
    try rejectUnknownKeys(decoder, CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    enable = try container.value(.enable, default: enable)
    width = try container.value(.width, default: width)
    opacity = try container.value(.opacity, default: opacity)
    color = try container.optional(RGB.self, .color)
    colorEnd = try container.optional(RGB.self, .colorEnd)
    guard width > 0 else {
      throw DecodingError.dataCorruptedError(
        forKey: .width, in: container, debugDescription: "must be more than 0")
    }
    guard (0...1).contains(opacity) else {
      throw DecodingError.dataCorruptedError(
        forKey: .opacity, in: container, debugDescription: "must be from 0 to 1")
    }
  }
}

extension AppearConfig: Decodable {
  enum CodingKeys: String, CodingKey, CaseIterable {
    case enable, floatingApps
  }

  public init(from decoder: any Decoder) throws {
    try rejectUnknownKeys(decoder, CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    enable = try container.value(.enable, default: enable)
    floatingApps = try container.optional([String].self, .floatingApps)
  }
}

extension DisplaysConfig: Decodable {
  enum CodingKeys: String, CodingKey, CaseIterable {
    case enable, wallpaper, place
  }

  public init(from decoder: any Decoder) throws {
    try rejectUnknownKeys(decoder, CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    enable = try container.value(.enable, default: enable)
    wallpaper = try container.optional(String.self, .wallpaper)
    place = try container.value(.place, default: place)
  }
}

extension DisplayPlacement: Decodable {
  enum CodingKeys: String, CodingKey, CaseIterable {
    case display, position, align
  }

  private struct Monitor: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
      case vendor, model, serial
    }

    let vendor: UInt32
    let model: UInt32
    let serial: UInt32

    init(from decoder: any Decoder) throws {
      try rejectUnknownKeys(decoder, CodingKeys.self)
      let container = try decoder.container(keyedBy: CodingKeys.self)
      vendor = try container.required(UInt32.self, .vendor)
      model = try container.required(UInt32.self, .model)
      serial = try container.required(UInt32.self, .serial)
    }
  }

  public init(from decoder: any Decoder) throws {
    try rejectUnknownKeys(decoder, CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let name = try? container.required(String.self, .display) {
      guard name == "sidecar" else {
        throw DecodingError.dataCorruptedError(
          forKey: .display, in: container,
          debugDescription: "must be \"sidecar\" or { vendor, model, serial }")
      }
      display = .sidecar
    } else {
      let monitor = try container.required(Monitor.self, .display)
      display = .monitor(vendor: monitor.vendor, model: monitor.model, serial: monitor.serial)
    }
    position = try container.required(Position.self, .position)
    align = try container.value(.align, default: .center)
    let fits: Set<Alignment> =
      switch position {
      case .above, .below: [.left, .right, .center]
      case .left, .right: [.top, .bottom, .center]
      }
    guard fits.contains(align) else {
      throw DecodingError.dataCorruptedError(
        forKey: .align, in: container,
        debugDescription: "must be one of \(fits.map(\.rawValue).sorted()) for \(position.rawValue)"
      )
    }
  }
}

extension DisplayPlacement.Position: Decodable {}
extension DisplayPlacement.Alignment: Decodable {}

extension FocusRule: Decodable {
  enum CodingKeys: String, CodingKey, CaseIterable {
    case match = "if"
    case enter, leave
  }

  private struct Match: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
      case appId, titleRegex
    }

    let appId: String?
    let titleRegex: String?

    init(from decoder: any Decoder) throws {
      try rejectUnknownKeys(decoder, CodingKeys.self)
      let container = try decoder.container(keyedBy: CodingKeys.self)
      appId = try container.optional(String.self, .appId)
      titleRegex = try container.optional(String.self, .titleRegex)
      if let titleRegex {
        do {
          _ = try Regex(titleRegex)
        } catch {
          throw DecodingError.dataCorruptedError(
            forKey: .titleRegex, in: container,
            debugDescription: "not a regular expression: \(error)")
        }
      }
    }
  }

  public init(from decoder: any Decoder) throws {
    try rejectUnknownKeys(decoder, CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let match = try container.required(Match.self, .match)
    guard match.appId != nil || match.titleRegex != nil else {
      throw DecodingError.dataCorruptedError(
        forKey: .match, in: container, debugDescription: "needs app-id, title-regex or both")
    }
    appId = match.appId
    titleRegex = match.titleRegex
    enter = try container.value(.enter, default: [])
    leave = try container.value(.leave, default: [])
    for key in [CodingKeys.enter, .leave] {
      let commands = key == .enter ? enter : leave
      guard commands.allSatisfy({ !$0.isEmpty }) else {
        throw DecodingError.dataCorruptedError(
          forKey: key, in: container, debugDescription: "a command cannot be empty")
      }
    }
  }
}

// MARK: - Helpers

/// A key the file has but its table does not.
private struct UnknownKey: Error {
  /// Where the key is, as `describe(_:)` puts it
  let location: String
}

/// Any key at all, to list the keys a table holds.
struct AnyKey: CodingKey {
  let stringValue: String
  let intValue: Int?

  init(stringValue: String) {
    self.stringValue = stringValue
    intValue = nil
  }

  init?(intValue: Int) {
    stringValue = String(intValue)
    self.intValue = intValue
  }
}

/// Throws for the first key in `decoder`'s table that is not one of `Keys`.
private func rejectUnknownKeys<Keys: CodingKey & CaseIterable>(
  _ decoder: any Decoder, _: Keys.Type
) throws {
  let known = Set(Keys.allCases.map(\.stringValue))
  let present = try decoder.container(keyedBy: AnyKey.self).allKeys
  if let unknown = present.map(\.stringValue).sorted().first(where: { !known.contains($0) }) {
    throw UnknownKey(location: describe(decoder.codingPath + [AnyKey(stringValue: unknown)]))
  }
}

// Decoding a key through these says what was expected there when the value is of another type.
// TOMLDecoder reports a string where a number belongs as a missing date-time, the last type it
// tried, so the error is put back in terms of the type asked for.
extension KeyedDecodingContainer {
  fileprivate func value<T: Decodable>(_ key: Key, default value: T) throws -> T {
    try optional(T.self, key) ?? value
  }

  fileprivate func optional<T: Decodable>(_ type: T.Type, _ key: Key) throws -> T? {
    do {
      return try decodeIfPresent(type, forKey: key)
    } catch let error as DecodingError {
      throw retyped(error, as: type, at: codingPath + [key])
    }
  }

  fileprivate func required<T: Decodable>(_ type: T.Type, _ key: Key) throws -> T {
    do {
      return try decode(type, forKey: key)
    } catch let error as DecodingError {
      throw retyped(error, as: type, at: codingPath + [key])
    }
  }
}

/// `error` as a type mismatch against `type`, when it is about the value at `path` itself rather
/// than something inside it.
private func retyped(_ error: DecodingError, as type: Any.Type, at path: [any CodingKey])
  -> DecodingError
{
  switch error {
  case .typeMismatch(_, let context), .valueNotFound(_, let context):
    guard context.codingPath.map(\.stringValue) == path.map(\.stringValue) else { return error }
    return .typeMismatch(
      type, .init(codingPath: path, debugDescription: context.debugDescription))
  default:
    return error
  }
}

/// A file key as the Swift name: `notification-center-key` becomes `notificationCenterKey`.
private func camelCase(_ key: String) -> String {
  let words = key.split(separator: "-", omittingEmptySubsequences: false)
  return words.enumerated().map { $0.offset == 0 ? String($0.element) : $0.element.capitalized }
    .joined()
}

/// A Swift name as the file key: `notificationCenterKey` becomes `notification-center-key`.
private func kebabCase(_ name: String) -> String {
  name.reduce(into: "") { result, character in
    if character.isUppercase {
      result += "-" + character.lowercased()
    } else {
      result.append(character)
    }
  }
}

/// Where `path` is in the file: `bar.accent`, `focus-rule[1].enter`.
private func describe(_ path: [any CodingKey]) -> String {
  path.reduce(into: "") { result, key in
    if let index = key.intValue {
      result += "[\(index)]"
    } else {
      result += (result.isEmpty ? "" : ".") + kebabCase(key.stringValue)
    }
  }
}

private func describe(_ error: DecodingError) -> String {
  switch error {
  case .typeMismatch(let type, let context):
    "\(describe(context.codingPath)): expected \(typeName(type))"
  case .valueNotFound(let type, let context):
    "\(describe(context.codingPath)): expected \(typeName(type))"
  case .keyNotFound(let key, let context):
    "\(describe(context.codingPath + [key])): missing"
  case .dataCorrupted(let context) where context.underlyingError is TOMLError:
    String(describing: context.underlyingError!)
  case .dataCorrupted(let context):
    "\(describe(context.codingPath)): \(context.debugDescription)"
  @unknown default:
    String(describing: error)
  }
}

private func typeName(_ type: Any.Type) -> String {
  switch type {
  case is String.Type: "a string"
  case is Bool.Type: "true or false"
  case is Double.Type: "a number"
  case is Int.Type, is UInt32.Type: "an integer"
  case is [String].Type: "a list of strings"
  case is [[String]].Type: "a list of commands, each a list of strings"
  case is RGB.Type: "a colour as \"RRGGBB\""
  default: "a \(type)"
  }
}
