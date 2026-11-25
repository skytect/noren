import NorenCore

/// The parts `config` turns on, in the order they start.
func makeParts(config: Config, aeroSpace: AeroSpaceClient) -> [any Part] {
  var parts: [any Part] = []
  // Before the bar, which has it stay put for a workspace picked with the pointer
  let pointer = config.pointer.enable ? Pointer(aeroSpace: aeroSpace) : nil
  if !config.focusRules.isEmpty {
    parts.append(FocusRules(rules: config.focusRules, aeroSpace: aeroSpace))
  }
  if config.strip.enable {
    parts.append(Strip(aeroSpace: aeroSpace))
  }
  if config.stay.enable {
    parts.append(Stay(config: config.stay, aeroSpace: aeroSpace))
  }
  if let pointer {
    parts.append(pointer)
  }
  return parts
}
