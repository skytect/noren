// What noren learns from AeroSpace's own config, so the same fact is not written twice: which apps
// float, and which keys close a window.
import TOMLDecoder

/// The facts noren reads from AeroSpace's config file.
public struct AeroSpaceConfigFacts: Equatable, Sendable {
  /// Apps AeroSpace floats by app id alone: an `on-window-detected` rule whose only condition is
  /// `app-id` and whose only command is `layout floating`. A rule that also tests a title or a
  /// workspace floats only some of the app's windows, so it does not count.
  public let floatingApps: Set<String>
  /// The bindings, in any mode, whose commands include `close`.
  public let closeBindings: Set<String>

  /// The facts in AeroSpace's config `toml`.
  public init(toml: String) throws(ConfigError) {
    let config: AeroSpaceConfig
    do {
      config = try TOMLDecoder().decode(AeroSpaceConfig.self, from: toml)
    } catch let error as TOMLError {
      throw ConfigError("AeroSpace's config: \(error.description)")
    } catch {
      throw ConfigError("AeroSpace's config: \(error)")
    }
    floatingApps = Set(
      config.onWindowDetected.compactMap { rule in
        rule.conditions?.keys == ["app-id"] && rule.commands == ["layout floating"]
          ? rule.conditions?.appId : nil
      })
    closeBindings = Set(
      config.modes.values.flatMap { mode in
        mode.bindings.filter { $0.value.contains { $0.split(separator: " ").first == "close" } }
          .keys
      })
  }
}

/// The parts of aerospace.toml read here; AeroSpace's other keys are left alone.
private struct AeroSpaceConfig: Decodable {
  struct Rule: Decodable {
    enum CodingKeys: String, CodingKey {
      case conditions = "if"
      case commands = "run"
    }

    /// A rule's `if` table: which conditions it has, and its app id if it has one.
    struct Conditions: Decodable {
      let keys: [String]
      let appId: String?

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        keys = container.allKeys.map(\.stringValue)
        appId = try container.decodeIfPresent(String.self, forKey: AnyKey(stringValue: "app-id"))
      }
    }

    let conditions: Conditions?
    let commands: [String]

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      conditions = try container.decodeIfPresent(Conditions.self, forKey: .conditions)
      commands = try container.decode(Commands.self, forKey: .commands).list
    }
  }

  struct Mode: Decodable {
    enum CodingKeys: String, CodingKey {
      case bindings = "binding"
    }

    let bindings: [String: [String]]

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      bindings =
        try container.decodeIfPresent([String: Commands].self, forKey: .bindings)?.mapValues(\.list)
        ?? [:]
    }
  }

  /// A command, or a list of them: AeroSpace takes both.
  struct Commands: Decodable {
    let list: [String]

    init(from decoder: any Decoder) throws {
      if let one = try? decoder.singleValueContainer().decode(String.self) {
        list = [one]
        return
      }
      var container = try decoder.unkeyedContainer()
      var list: [String] = []
      while !container.isAtEnd {
        list.append(try container.decode(String.self))
      }
      self.list = list
    }
  }

  enum CodingKeys: String, CodingKey {
    case onWindowDetected = "on-window-detected"
    case modes = "mode"
  }

  let onWindowDetected: [Rule]
  let modes: [String: Mode]

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    onWindowDetected = try container.decodeIfPresent([Rule].self, forKey: .onWindowDetected) ?? []
    modes = try container.decodeIfPresent([String: Mode].self, forKey: .modes) ?? [:]
  }
}
