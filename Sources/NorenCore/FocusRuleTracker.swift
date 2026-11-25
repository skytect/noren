/// The focused window, as far as focus rules look at it.
public struct FocusedWindow: Equatable, Sendable {
  public let appId: String?
  public let title: String

  public init(appId: String?, title: String) {
    self.appId = appId
    self.title = title
  }
}

/// Which focus rules the focused window is inside, and the commands moving focus runs.
public struct FocusRuleTracker {
  private let rules: [FocusRule]
  private let titles: [Regex<AnyRegexOutput>?]
  private var inside: [Bool]

  /// Tracks `rules`, whose title expressions Config has already checked.
  public init(rules: [FocusRule]) {
    self.rules = rules
    titles = rules.map { rule in rule.titleRegex.map { try! Regex($0) } }
    inside = Array(repeating: false, count: rules.count)
  }

  /// The commands for focus having moved to `window` (nil when no window is focused): the leave
  /// commands of the rules focus left, then the enter commands of the rules it entered.
  public mutating func focus(_ window: FocusedWindow?) -> [[String]] {
    let now = rules.indices.map { index in window.map { matches(rule: index, $0) } ?? false }
    defer { inside = now }
    let left = rules.indices.filter { inside[$0] && !now[$0] }.flatMap { rules[$0].leave }
    let entered = rules.indices.filter { !inside[$0] && now[$0] }.flatMap { rules[$0].enter }
    return left + entered
  }

  /// The commands that put things as `window` wants them when what was run before is unknown, as
  /// when noren starts: every rule's leave commands where the window is outside it, then the
  /// enter commands where it is inside.
  public mutating func reset(_ window: FocusedWindow?) -> [[String]] {
    inside = rules.indices.map { index in !(window.map { matches(rule: index, $0) } ?? false) }
    return focus(window)
  }

  private func matches(rule index: Int, _ window: FocusedWindow) -> Bool {
    let rule = rules[index]
    if let appId = rule.appId, appId != window.appId { return false }
    if let title = titles[index], (try? title.firstMatch(in: window.title)) == nil { return false }
    return true
  }
}
