// One screen's bar and the backdrop behind its windows.
//
// The backdrop covers the whole screen just over the desktop icons, under every window, and is
// black while the screen's workspace has tiled windows, so the gaps between them are. The bar is
// a panel over the menu bar, painting what is behind it: the wallpaper as the desktop fills the
// screen, and over it a black layer that fades with the backdrop.
import AppKit
import ImageIO
import NorenCore
import QuartzCore

final class BarScreen {
  /// How long the backdrop, and the bar coming back over the menu bar, take to fade.
  private static let fade: TimeInterval = 0.15
  /// Two over the desktop icons: over the shade macOS draws under the menu bar (the window
  /// server's "underbelly", one over the icons), which would show through the gaps between
  /// windows, and under every app's windows.
  private static let backdropLevel = NSWindow.Level(
    rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)
  /// Above the menu bar's windows (the menu bar's own, and those at the status level and the one
  /// above), which would otherwise take the bar's clicks; below menus and popovers.
  private static let level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)

  /// The screen's place in NSScreen.screens.
  let index: Int
  let panel: NSPanel
  private let backdrop: NSWindow
  private let screen: NSScreen
  /// The screen's wallpaper, the whole screen of it, its top under the bar.
  private let wallpaper = CALayer()
  /// The wallpaper and, for one that changes with the time of day, the frame the layer shows
  private var shown: (url: URL?, frame: Int)?
  /// Shows the next frame of a wallpaper that changes with the time of day, when it is due
  private var nextFrame: Timer?
  /// Over the wallpaper in the bar, shown with the backdrop.
  private let black = CALayer()
  private let view: BarView

  /// The bar and backdrop for `screen`: the bar at least `minimumHeight` high, and at least its
  /// own menu bar's height, which macOS keeps windows below.
  init(screen: NSScreen, index: Int, minimumHeight: CGFloat, bar: Bar, busy: Bool) {
    self.index = index
    self.screen = screen
    let frame = screen.frame

    backdrop = NSWindow(
      contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    backdrop.ignoresMouseEvents = true
    backdrop.alphaValue = busy ? 1 : 0
    Self.configure(backdrop, frame: frame, level: Self.backdropLevel)

    let height = max(minimumHeight, frame.maxY - screen.visibleFrame.maxY)
    let barFrame = NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
    panel = NSPanel(
      contentRect: barFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    let content = NSView(frame: NSRect(x: 0, y: 0, width: frame.width, height: height))
    content.wantsLayer = true
    content.layer?.masksToBounds = true
    wallpaper.contentsGravity = .resizeAspectFill
    wallpaper.frame = CGRect(
      x: 0, y: height - frame.height, width: frame.width, height: frame.height)
    content.layer?.addSublayer(wallpaper)
    black.frame = CGRect(x: 0, y: 0, width: frame.width, height: height)
    black.backgroundColor = CGColor.black
    black.opacity = busy ? 1 : 0
    content.layer?.addSublayer(black)
    view = BarView(
      frame: NSRect(x: 0, y: 0, width: frame.width, height: height), screen: screen,
      index: index, bar: bar)
    content.addSubview(view)
    panel.contentView = content
    Self.configure(panel, frame: barFrame, level: Self.level)
    showCurrentWallpaper()
  }

  func close() {
    nextFrame?.invalidate()
    panel.close()
    backdrop.close()
  }

  /// Redraws the bar, and fades the backdrop and the bar's black in or out with `busy`.
  func show(busy: Bool) {
    view.needsDisplay = true
    showCurrentWallpaper()
    let alpha: CGFloat = busy ? 1 : 0
    guard backdrop.alphaValue != alpha else { return }
    let timing = CAMediaTimingFunction(name: .easeInEaseOut)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.fade
      context.timingFunction = timing
      backdrop.animator().alphaValue = alpha
    }
    CATransaction.begin()
    CATransaction.setAnimationDuration(Self.fade)
    CATransaction.setAnimationTimingFunction(timing)
    black.opacity = Float(alpha)
    CATransaction.commit()
  }

  /// Paints the screen's wallpaper as it is now. It changes under noren: the displays part sets it
  /// after the bar has started, System Settings sets it at any time, and a dynamic wallpaper
  /// changes frame with the time of day.
  private func showCurrentWallpaper() {
    let url = NSWorkspace.shared.desktopImageURL(for: screen)
    let wallpaperFile = Wallpaper.read(url)
    var frame = 0
    nextFrame?.invalidate()
    nextFrame = nil
    if let schedule = wallpaperFile?.schedule {
      let midnight = Calendar.current.startOfDay(for: Date())
      let now = Date().timeIntervalSince(midnight) / 86400
      frame = schedule.frame(at: now)
      let due = midnight.addingTimeInterval(schedule.nextChange(after: now) * 86400)
      nextFrame = Timer.scheduledTimer(
        withTimeInterval: due.timeIntervalSinceNow, repeats: false
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.showCurrentWallpaper() }
      }
    }
    guard shown?.url != url || shown?.frame != frame else { return }
    shown = (url, frame)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    wallpaper.contents = wallpaperFile?.image(frame)
    CATransaction.commit()
  }

  /// Brings the bar back over the menu bar, fading it in.
  func fadeIn() {
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.fade
      panel.animator().alphaValue = 1
    }
  }

  /// Black, borderless, on every Space, never activating or taking part in window cycling.
  private static func configure(_ window: NSWindow, frame: NSRect, level: NSWindow.Level) {
    window.isReleasedWhenClosed = false
    window.backgroundColor = .black
    window.isOpaque = false
    window.hasShadow = false
    window.level = level
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    window.setFrame(frame, display: true)
    window.orderFrontRegardless()
  }
}

/// The wallpaper file, kept once read: a whole screen's image takes a while to decode. Its image
/// for one frame is kept too, the frame the screens show.
private final class Wallpaper {
  private static var last: Wallpaper?

  let url: URL
  /// For a wallpaper that changes with the time of day
  let schedule: WallpaperSchedule?
  private let source: CGImageSource
  private var decoded: (frame: Int, image: CGImage?)?

  private init?(url: URL) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    self.url = url
    self.source = source
    schedule = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
      .flatMap {
        CGImageMetadataCopyStringValueWithPath($0, nil, "apple_desktop:h24" as CFString)
      }
      .flatMap { WallpaperSchedule(h24: $0 as String) }
  }

  static func read(_ url: URL?) -> Wallpaper? {
    guard let url else { return nil }
    if last?.url != url { last = Wallpaper(url: url) }
    return last
  }

  func image(_ frame: Int) -> CGImage? {
    if decoded?.frame != frame {
      decoded = (frame, CGImageSourceCreateImageAtIndex(source, frame, nil))
    }
    return decoded?.image
  }
}
