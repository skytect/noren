import CoreGraphics
import NorenCore

/// The parts `config` turns on, in the order they start and are handed each event: the
/// Objective-C noren's order, with Appear last (see below).
func makeParts(config: Config, aeroSpace: AeroSpaceClient) -> [any Part] {
  var parts: [any Part] = []
  // Parts that reach one another do so through closures over these, so any of them can be off
  // Made last, below
  var appear: Appear?

  if config.dwindle.enable {
    parts.append(Dwindle(aeroSpace: aeroSpace, show: { appear?.show($0, fade: $1) }))
  }
  if !config.focusRules.isEmpty {
    parts.append(FocusRules(rules: config.focusRules, aeroSpace: aeroSpace))
  }
  if config.restore.enable {
    parts.append(Restore(aeroSpace: aeroSpace))
  }
  if config.displays.enable {
    parts.append(Displays(config: config.displays))
  }
  // After every part that opens windows: the payload hides none of noren's own while Appear's port
  // is not there yet
  if config.appear.enable {
    let made = Appear(config: config.appear, aeroSpace: aeroSpace, wakeBorder: {})
    appear = made
    parts.append(made)
  }
  return parts
}
