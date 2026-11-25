// `noren display-mode`: the built-in screen's sizes, and changing to one of them.
import CoreGraphics
import NorenCore

enum DisplayModeCommand {
  static func run(_ arguments: [String]) -> Int32 {
    guard let display = builtInDisplay() else {
      return Commands.fail("display-mode: no built-in display (lid closed?)")
    }
    let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
    let available = (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] ?? [])
      .filter { $0.isUsableForDesktopGUI() }
    let modes = available.map(DisplayMode.init)
    let current = CGDisplayCopyDisplayMode(display).map(DisplayMode.init)

    switch arguments.count {
    case 0:
      for mode in DisplayMode.bestForEachSize(of: modes) {
        let marker =
          mode.width == current?.width && mode.height == current?.height ? "  current" : ""
        print(
          "\(mode.width) \(mode.height)  (\(mode.pixelWidth)x\(mode.pixelHeight) pixels, "
            + "\(Int(mode.refreshRate.rounded())) Hz)\(marker)")
      }
      return 0
    case 2:
      guard let width = Int(arguments[0]), let height = Int(arguments[1]) else { break }
      guard let pick = DisplayMode.best(width: width, height: height, of: modes),
        let index = modes.firstIndex(of: pick)
      else {
        return Commands.fail(
          "display-mode: the built-in display has no \(width)x\(height) size; run without "
            + "arguments to list them")
      }
      if current?.width == width && current?.height == height { return 0 }
      var configuration: CGDisplayConfigRef?
      guard CGBeginDisplayConfiguration(&configuration) == .success else {
        return Commands.fail("display-mode: could not begin a display configuration")
      }
      CGConfigureDisplayWithDisplayMode(configuration, display, available[index], nil)
      let error = CGCompleteDisplayConfiguration(configuration, .permanently)
      guard error == .success else {
        return Commands.fail("display-mode: could not change the mode (error \(error.rawValue))")
      }
      return 0
    default:
      break
    }
    return Commands.fail("usage: noren display-mode [WIDTH HEIGHT]", status: 2)
  }

  private static func builtInDisplay() -> CGDirectDisplayID? {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
    return displays.first { CGDisplayIsBuiltin($0) != 0 }
  }
}

extension DisplayMode {
  init(_ mode: CGDisplayMode) {
    self.init(
      width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth,
      pixelHeight: mode.pixelHeight, refreshRate: mode.refreshRate)
  }
}
