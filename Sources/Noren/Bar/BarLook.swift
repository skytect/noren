// What the bar draws with: its colours, and the apps' icons.
import AppKit
import NorenCore

/// The bar's colours: the config's, else the defaults docs/configuration.md gives.
struct BarColors {
  /// The focused workspace's chip.
  let accent: NSColor
  let text: NSColor
  /// Workspaces not on screen, a window's title, items that are off.
  let dim: NSColor
  /// The mode's chip, and items that need a look.
  let warn: NSColor
  /// Ink on the accent's chip.
  let base: NSColor

  init(_ config: BarConfig) {
    accent = config.accent.map { NSColor($0) } ?? .systemBlue
    text = config.text.map { NSColor($0) } ?? NSColor(white: 0.85, alpha: 1)
    dim = config.dim.map { NSColor($0) } ?? NSColor(white: 0.5, alpha: 1)
    warn = config.warn.map { NSColor($0) } ?? .systemYellow
    base = config.base.map { NSColor($0) } ?? .black
  }
}

/// Apps' icons by AppKey, each looked up once found.
final class AppIcons {
  private var cache: [AppKey: NSImage] = [:]

  /// The icon of the app `key` names, found through its process `pid` or, failing that, its
  /// bundle id; nil when neither finds one.
  func icon(_ key: AppKey, pid: Int32?) -> NSImage? {
    if let icon = cache[key] { return icon }
    var icon = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.icon }
    if icon == nil, case .bundle(let bundleId) = key,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    {
      icon = NSWorkspace.shared.icon(forFile: url.path)
    }
    cache[key] = icon
    return icon
  }
}
