// The strip itself: a glass pill near the bottom of a screen, a slot per workspace, and a
// selection that slides between the slots.
import AppKit

final class StripPanel {
  private static let slotWidth: CGFloat = 40
  private static let height: CGFloat = 44
  /// Between the strip's ends and its first and last slot
  private static let padding: CGFloat = 6
  /// Above the bottom of the screen
  private static let bottom: CGFloat = 84
  private static let fadeIn: TimeInterval = 0.1
  private static let fadeOut: TimeInterval = 0.25
  private static let slide: TimeInterval = 0.3

  private let panel: NSPanel
  private let selection = CALayer()
  private var labels: [CATextLayer] = []
  /// The workspaces laid out, and the display they are on
  private(set) var names: [String] = []
  private var display: CGDirectDisplayID?
  /// A newer show or hide cancels an older pending hide
  private var hideGeneration = 0
  private(set) var isShown = false

  init() {
    let frame = NSRect(x: 0, y: 0, width: 100, height: Self.height)
    panel = NSPanel(
      contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.ignoresMouseEvents = true
    panel.level = .popUpMenu
    panel.collectionBehavior = [
      .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
    ]
    panel.alphaValue = 0

    let glass = NSVisualEffectView(frame: frame)
    glass.material = .hudWindow
    glass.blendingMode = .behindWindow
    glass.state = .active
    glass.appearance = NSAppearance(named: .darkAqua)
    glass.maskImage = Self.pillMask(height: Self.height)
    panel.contentView = glass

    let content = NSView(frame: glass.bounds)
    content.autoresizingMask = [.width, .height]
    content.wantsLayer = true
    glass.addSubview(content)

    selection.backgroundColor = NSColor(white: 1, alpha: 0.18).cgColor
    selection.cornerRadius = (Self.height - 10) / 2
    content.layer?.addSublayer(selection)
  }

  private static func pillMask(height: CGFloat) -> NSImage {
    let radius = height / 2
    let pill = NSImage(size: NSSize(width: 2 * radius + 1, height: height), flipped: false) {
      rect in
      NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
      return true
    }
    pill.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    pill.resizingMode = .stretch
    return pill
  }

  /// Whether the strip is laid out on `screen`.
  func isLaidOut(on screen: NSScreen) -> Bool {
    display == screen.displayID
  }

  /// Moves the selection to `position` in slots (a whole number is on a workspace) and brightens
  /// the labels near it.
  func place(_ position: Double, animated: Bool) {
    CATransaction.begin()
    if animated {
      CATransaction.setAnimationDuration(Self.slide)
      CATransaction.setAnimationTimingFunction(
        CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1))
    } else {
      CATransaction.setDisableActions(true)
    }
    selection.frame = CGRect(
      x: Self.padding + position * Self.slotWidth + 3, y: 5, width: Self.slotWidth - 6,
      height: Self.height - 10)
    for (index, label) in labels.enumerated() {
      label.opacity = Float(0.45 + 0.55 * max(0, 1 - abs(Double(index) - position)))
    }
    CATransaction.commit()
  }

  /// Lays the strip out for `names` on `screen`, unless it already is.
  func layOut(_ names: [String], on screen: NSScreen) {
    guard names != self.names || !isLaidOut(on: screen) else { return }
    self.names = names
    display = screen.displayID
    for label in labels { label.removeFromSuperlayer() }
    labels.removeAll()
    let font = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
    let textHeight = ceil(font.ascender - font.descender)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for (index, name) in names.enumerated() {
      let label = CATextLayer()
      label.string = name
      label.font = font
      label.fontSize = font.pointSize
      label.foregroundColor = NSColor.white.cgColor
      label.alignmentMode = .center
      label.contentsScale = screen.backingScaleFactor
      label.frame = CGRect(
        x: Self.padding + CGFloat(index) * Self.slotWidth, y: (Self.height - textHeight) / 2,
        width: Self.slotWidth, height: textHeight)
      selection.superlayer?.addSublayer(label)
      labels.append(label)
    }
    CATransaction.commit()
    let width = 2 * Self.padding + CGFloat(names.count) * Self.slotWidth
    let frame = screen.frame
    panel.setFrame(
      NSRect(
        x: (frame.midX - width / 2).rounded(), y: frame.minY + Self.bottom, width: width,
        height: Self.height), display: true)
    panel.invalidateShadow()
  }

  func show() {
    hideGeneration += 1
    if !isShown {
      isShown = true
      panel.orderFrontRegardless()
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.fadeIn
      panel.animator().alphaValue = 1
    }
  }

  /// Fades the strip out after `delay`, unless it is shown or hidden again meanwhile.
  func hide(after delay: Duration) {
    hideGeneration += 1
    let generation = hideGeneration
    Task {
      try? await Task.sleep(for: delay)
      guard generation == hideGeneration else { return }
      await NSAnimationContext.runAnimationGroup { context in
        context.duration = Self.fadeOut
        panel.animator().alphaValue = 0
      }
      guard generation == hideGeneration else { return }
      panel.orderOut(nil)
      isShown = false
    }
  }
}
