import NorenCore

/// The parts `config` turns on, in the order they start.
func makeParts(config: Config, aeroSpace: AeroSpaceClient) -> [any Part] {
  var parts: [any Part] = []
  if !config.focusRules.isEmpty {
    parts.append(FocusRules(rules: config.focusRules, aeroSpace: aeroSpace))
  }
  if config.displays.enable {
    parts.append(Displays(config: config.displays))
  }
  if config.restore.enable {
    parts.append(Restore(aeroSpace: aeroSpace))
  }
  return parts
}
