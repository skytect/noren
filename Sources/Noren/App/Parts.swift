import NorenCore

/// The parts `config` turns on, in the order they start.
func makeParts(config: Config, aeroSpace: AeroSpaceClient) -> [any Part] {
  var parts: [any Part] = []
  // Made last, below; Dwindle asks it to show the windows it placed
  var appear: Appear?
  if !config.focusRules.isEmpty {
    parts.append(FocusRules(rules: config.focusRules, aeroSpace: aeroSpace))
  }
  if config.dwindle.enable {
    parts.append(Dwindle(aeroSpace: aeroSpace, show: { appear?.show($0, fade: $1) }))
  }
  // After every part that opens windows: the payload hides none of noren's own while Appear's port
  // is not there yet
  if config.appear.enable {
    let made = Appear(
      config: config.appear, aeroSpace: aeroSpace,
      wakeBorder: {})  // wired when Border lands
    appear = made
    parts.append(made)
  }
  return parts
}
