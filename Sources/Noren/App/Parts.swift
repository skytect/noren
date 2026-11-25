import NorenCore

/// The parts `config` turns on, in the order they start.
func makeParts(config: Config, aeroSpace: AeroSpaceClient) -> [any Part] {
  var parts: [any Part] = []
  if config.bar.enable {
    parts.append(
      Bar(
        config: config.bar, showsStatus: config.status.enable, aeroSpace: aeroSpace,
        // wired when Pointer lands
        stayPointer: { _ in }))
  }
  if !config.focusRules.isEmpty {
    parts.append(FocusRules(rules: config.focusRules, aeroSpace: aeroSpace))
  }
  return parts
}
