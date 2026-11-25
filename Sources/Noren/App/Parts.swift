import NorenCore

/// The parts `config` turns on, in the order they start.
func makeParts(config: Config, aeroSpace: AeroSpaceClient) -> [any Part] {
  var parts: [any Part] = []
  if !config.focusRules.isEmpty {
    parts.append(FocusRules(rules: config.focusRules, aeroSpace: aeroSpace))
  }
  // wired when Appear lands: isHeld becomes `{ appear?.holds($0) ?? false }`
  let border =
    config.border.enable
    ? Border(config: config.border, aeroSpace: aeroSpace, isHeld: { _ in false }) : nil
  if let border { parts.append(border) }
  if config.drag.enable {
    parts.append(Drag())
  }
  return parts
}
