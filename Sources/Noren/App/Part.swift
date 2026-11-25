import NorenCore

/// One of noren's parts: the bar, the strip, the border and so on. Each is made from its config
/// section in makeParts, started once, then handed every AeroSpace event, all on the main actor.
protocol Part: AnyObject {
  /// Starts the part. Called once, before any event.
  func start()
  /// Follows `event`; `.connected` first, and again each time AeroSpace comes back.
  func handle(_ event: AeroSpaceEvent)
}

extension Part {
  func start() {}
  func handle(_ event: AeroSpaceEvent) {}
}
