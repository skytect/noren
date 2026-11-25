import AppKit
import NorenCore

extension NSColor {
  /// `rgb` from the config, in sRGB.
  convenience init(_ rgb: RGB, alpha: CGFloat = 1) {
    self.init(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
  }
}
