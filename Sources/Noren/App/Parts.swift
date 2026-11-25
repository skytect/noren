import NorenCore

/// The parts `config` turns on, in the order they start.
func makeParts(config: Config, aeroSpace: AeroSpaceClient) -> [any Part] {
  var parts: [any Part] = []
  if !config.focusRules.isEmpty {
    parts.append(FocusRules(rules: config.focusRules, aeroSpace: aeroSpace))
  }
  if config.strip.enable {
    parts.append(Strip(aeroSpace: aeroSpace))
  }
  if config.stay.enable {
    parts.append(Stay(config: config.stay, aeroSpace: aeroSpace))
  }
  return parts
}
