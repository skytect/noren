// What one screen's bar draws, and its clicks and scrolls. Beside a notch the left side goes left
// of it and the right side right of it; without one, each takes half the screen.
//
// On a busy screen (black behind) the bar uses the configured colours. On the wallpaper the
// configured greys can vanish, so it inks white over a soft shadow instead, as the macOS menu bar
// does. Chips are filled, so they and their labels go without the shadow.
import AppKit
import NorenCore

final class BarView: NSView {
  /// Between the screen's edges and what the bar draws.
  private static let edgeInset: CGFloat = 10
  /// Inactive workspaces' app icons.
  private static let inactiveIconAlpha: CGFloat = 0.7
  /// The right side's gaps: the clock to the first status item, between items, the items to the
  /// window's title.
  private static let clockGap: CGFloat = 16
  private static let statusGap: CGFloat = 10
  private static let titleGap: CGFloat = 18
  /// A trackpad swipe steps one workspace once its fingers have moved this far, in points.
  private static let scrollStep: CGFloat = 24
  /// A spun mouse wheel steps at most once in this long.
  private static let wheelInterval: TimeInterval = 0.15
  // The bar's look over the wallpaper
  private static let wallpaperDimAlpha: CGFloat = 0.75
  private static let wallpaperShadowAlpha: CGFloat = 0.6
  private static let wallpaperShadowBlur: CGFloat = 4

  private let screen: NSScreen
  private let index: Int
  private unowned let bar: Bar
  /// The workspace chips as drawn, for clicks.
  private var chips: [(rect: NSRect, workspace: String)] = []
  /// The clock, the status items, the menu bar button and the focused app as drawn.
  private var targets: [(rect: NSRect, action: () -> Void)] = []
  /// The trackpad swipe under way: how far its fingers have moved, and whether it has stepped.
  private var scrolled: CGFloat = 0
  private var stepped = false
  private var lastWheelStep: TimeInterval = 0

  init(frame: NSRect, screen: NSScreen, index: Int, bar: Bar) {
    self.screen = screen
    self.index = index
    self.bar = bar
    super.init(frame: frame)
  }

  required init?(coder: NSCoder) { fatalError("BarView is made in code") }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  /// The zones beside the notch, or the two halves of a screen without one, in view coordinates.
  private var zones: (left: NSRect, right: NSRect) {
    let left = screen.auxiliaryTopLeftArea ?? .zero
    let right = screen.auxiliaryTopRightArea ?? .zero
    if screen.safeAreaInsets.top > 0 && !left.isEmpty && !right.isEmpty {
      let originX = screen.frame.minX
      return (
        NSRect(x: left.minX - originX, y: 0, width: left.width, height: bounds.height),
        NSRect(x: right.minX - originX, y: 0, width: right.width, height: bounds.height)
      )
    }
    return (
      NSRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height),
      NSRect(x: bounds.width / 2, y: 0, width: bounds.width / 2, height: bounds.height)
    )
  }

  // MARK: Drawing

  /// The inks for one drawing of the bar.
  private struct Inks {
    let text: NSColor
    let dim: NSColor
    /// For text straight on the wallpaper; nil over black.
    let shadow: NSShadow?
  }

  override func draw(_ dirtyRect: NSRect) {
    // Clear: the black under a busy screen's bar is the backdrop's, so bar and screen fade
    // together
    NSColor.clear.setFill()
    bounds.fill(using: .copy)
    let busy = bar.state?.busyScreens.contains(index) ?? false
    let inks: Inks
    if busy {
      inks = Inks(text: bar.colors.text, dim: bar.colors.dim, shadow: nil)
    } else {
      let shadow = NSShadow()
      shadow.shadowColor = NSColor(white: 0, alpha: Self.wallpaperShadowAlpha)
      shadow.shadowBlurRadius = Self.wallpaperShadowBlur
      inks = Inks(
        text: .white, dim: NSColor(white: 1, alpha: Self.wallpaperDimAlpha), shadow: shadow)
    }
    let (left, right) = zones
    let modeX = drawChips(in: left, inks)
    drawMode(from: modeX, in: left)
    drawRight(in: right, inks)
  }

  /// Draws the workspace chips from the left zone's start, and returns where they end.
  private func drawChips(in left: NSRect, _ inks: Inks) -> CGFloat {
    chips = []
    var x = left.minX + Self.edgeInset
    guard let state = bar.state else { return x }
    let isFocusedScreen = state.focusedScreen == index
    let onScreen = state.visible[index]
    let names = state.chips[index] ?? []
    func ink(_ isVisible: Bool) -> NSColor {
      isVisible ? (isFocusedScreen ? bar.colors.base : inks.text) : inks.dim
    }
    let labels = names.map { name in
      let isVisible = name == onScreen
      return NSAttributedString(
        string: name,
        attributes: Self.attributes(Fonts.bold, ink(isVisible), isVisible ? nil : inks.shadow))
    }
    let icons = names.map { name in
      (state.apps[name] ?? []).compactMap { bar.icons.icon($0, pid: state.pids[$0]) }
    }
    let layout = ChipLayout(
      chips: zip(labels, icons).map { label, icons in
        ChipLayout.Chip(labelWidth: ceil(label.size().width), iconCount: icons.count)
      },
      room: left.width - 2 * Self.edgeInset,
      moreWidth: { ceil(Self.moreLabel($0, .white, nil).size().width) })
    let chipY = ((bounds.height - ChipLayout.height) / 2).rounded()
    for (i, name) in names.enumerated() {
      let isVisible = name == onScreen
      let chip = NSRect(x: x, y: chipY, width: layout.widths[i], height: ChipLayout.height)
      if chip.maxX > left.maxX - Self.edgeInset { break }
      if isVisible {
        Self.fillChip(chip, isFocusedScreen ? bar.colors.accent : NSColor(white: 1, alpha: 0.16))
      }
      let shown = min(icons[i].count, layout.iconLimit)
      let hidden = shown > 0 ? icons[i].count - shown : 0
      let more = Self.moreLabel(hidden, ink(isVisible), isVisible ? nil : inks.shadow)
      let labelWidth = ceil(labels[i].size().width)
      let content = ChipLayout.contentWidth(
        labelWidth: labelWidth, icons: shown, hidden: hidden,
        moreWidth: { _ in ceil(more.size().width) })
      var itemX = chip.midX - content / 2
      Self.drawText(labels[i], x: itemX, maxWidth: labelWidth, height: bounds.height)
      itemX += labelWidth + ChipLayout.labelIconGap
      for icon in icons[i].prefix(shown) {
        Self.drawIcon(
          icon, x: itemX, height: bounds.height, alpha: isVisible ? 1 : Self.inactiveIconAlpha)
        itemX += ChipLayout.iconSize + ChipLayout.iconGap
      }
      if hidden > 0 {
        Self.drawText(more, x: itemX, maxWidth: ceil(more.size().width), height: bounds.height)
      }
      chips.append((chip, name))
      x = chip.maxX + ChipLayout.gap
    }
    return x
  }

  /// Draws AeroSpace's mode after the chips while it is not the main one.
  private func drawMode(from x: CGFloat, in left: NSRect) {
    guard bar.mode != "main" else { return }
    let label = NSAttributedString(
      string: bar.mode.uppercased(), attributes: Self.attributes(Fonts.bold, bar.colors.base, nil))
    let labelWidth = ceil(label.size().width)
    let chip = NSRect(
      x: x + ChipLayout.gap, y: ((bounds.height - ChipLayout.height) / 2).rounded(),
      width: labelWidth + 2 * ChipLayout.padding, height: ChipLayout.height)
    guard chip.maxX <= left.maxX - Self.edgeInset else { return }
    Self.fillChip(chip, bar.colors.warn)
    Self.drawText(
      label, x: chip.minX + ChipLayout.padding, maxWidth: labelWidth, height: bounds.height)
  }

  /// Draws, from the right edge, the clock, the status items, then the focused window; and the
  /// menu bar button at the right zone's left end.
  private func drawRight(in right: NSRect, _ inks: Inks) {
    targets = []
    let height = bounds.height
    // Where the last thing drawn begins
    var rightX = right.maxX - Self.edgeInset
    let clock = NSAttributedString(
      string: bar.clock.text(), attributes: Self.attributes(Fonts.bold, inks.text, inks.shadow))
    let clockWidth = ceil(clock.size().width)
    rightX -= clockWidth
    Self.drawText(clock, x: rightX, maxWidth: clockWidth, height: height)
    addTarget(from: rightX, width: clockWidth) { [unowned bar] in
      bar.clock.openNotificationCenter()
    }
    var gap = Self.clockGap
    for item in (bar.status?.items ?? []).reversed() {
      let ink = toneColor(item.tone, inks)
      guard let symbol = Self.symbol(item.symbol, level: item.level, ink: ink) else { continue }
      let label = item.text.map {
        NSAttributedString(string: $0, attributes: Self.attributes(Fonts.regular, ink, inks.shadow))
      }
      let labelWidth = label.map { ceil($0.size().width) } ?? 0
      let width = symbol.size.width + (label != nil ? 4 + labelWidth : 0)
      rightX -= gap + width
      Self.drawWithShadow(inks.shadow) {
        symbol.draw(
          in: NSRect(
            x: rightX, y: ((height - symbol.size.height) / 2).rounded(), width: symbol.size.width,
            height: symbol.size.height))
      }
      if let label {
        Self.drawText(
          label, x: rightX + symbol.size.width + 4, maxWidth: labelWidth, height: height)
      }
      if let action = item.action {
        addTarget(from: rightX, width: width) { [unowned bar] in bar.status?.perform(action) }
      }
      gap = Self.statusGap
    }
    // The menu bar button, at the right zone's left end; the app may also be clicked
    var leftLimit = right.minX + Self.edgeInset
    if let menuBar = Self.symbol("menubar.arrow.down.rectangle", level: nil, ink: inks.text) {
      Self.drawWithShadow(inks.shadow) {
        menuBar.draw(
          in: NSRect(
            x: leftLimit, y: ((height - menuBar.size.height) / 2).rounded(),
            width: menuBar.size.width, height: menuBar.size.height))
      }
      addTarget(from: leftLimit, width: menuBar.size.width) { [unowned bar] in bar.uncover(true) }
      leftLimit += menuBar.size.width + Self.titleGap
    }
    guard let state = bar.state, state.focusedScreen == index, let focused = state.focused,
      !focused.name.isEmpty
    else { return }
    rightX -= Self.titleGap
    let window = NSMutableAttributedString(
      string: focused.name, attributes: Self.attributes(Fonts.bold, inks.text, inks.shadow))
    if !focused.title.isEmpty && focused.title != focused.name {
      window.append(
        NSAttributedString(
          string: "  " + focused.title,
          attributes: Self.attributes(Fonts.regular, inks.dim, inks.shadow)))
    }
    var room = rightX - leftLimit
    // The icon goes first to make room for the name
    let iconSpace = ChipLayout.iconSize + ChipLayout.labelIconGap
    var icon = bar.icons.icon(focused.key, pid: state.pids[focused.key])
    if room < iconSpace + 3 * ChipLayout.iconSize { icon = nil }
    if icon != nil { room -= iconSpace }
    let width = min(ceil(window.size().width), room)
    Self.drawText(window, x: rightX - width, maxWidth: width, height: height)
    if let icon, width > 0 {
      Self.drawIcon(icon, x: rightX - width - iconSpace, height: height, alpha: 1)
    }
    let appX = rightX - width - (icon != nil ? iconSpace : 0)
    if width > 0 {
      addTarget(from: appX, width: rightX - appX) { [unowned bar] in bar.uncover(true) }
    }
  }

  private func toneColor(_ tone: StatusTone, _ inks: Inks) -> NSColor {
    switch tone {
    case .normal: inks.text
    case .dim: inks.dim
    case .warn: bar.colors.warn
    case .microphone: .systemOrange
    case .camera: .systemGreen
    }
  }

  /// A click target `width` wide from `x`: the bar's whole height, and a little either side.
  private func addTarget(from x: CGFloat, width: CGFloat, action: @escaping () -> Void) {
    targets.append(
      (
        NSRect(
          x: x - Self.statusGap / 2, y: 0, width: width + Self.statusGap, height: bounds.height),
        action
      ))
  }

  // MARK: Clicks and scrolls

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if let chip = chips.first(where: { $0.rect.contains(point) }) {
      bar.switchTo(chip.workspace, onScreen: index)
    } else if let target = targets.first(where: { $0.rect.contains(point) }) {
      target.action()
    }
  }

  /// Scrolling over the workspaces steps through them. Scrolling towards later content (fingers
  /// up or left with natural scrolling) goes to the next one, as the three-finger swipe does. A
  /// trackpad swipe steps once however far it goes, and its momentum is ignored; a wheel steps
  /// once per notch.
  override func scrollWheel(with event: NSEvent) {
    guard zones.left.contains(convert(event.locationInWindow, from: nil)),
      event.momentumPhase.isEmpty
    else { return }
    let delta =
      abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
      ? event.scrollingDeltaX : event.scrollingDeltaY
    if event.phase.isEmpty {
      guard delta != 0, event.timestamp - lastWheelStep >= Self.wheelInterval else { return }
      lastWheelStep = event.timestamp
      step(delta < 0 ? 1 : -1)
      return
    }
    if !event.phase.isDisjoint(with: [.mayBegin, .began]) {
      scrolled = 0
      stepped = false
    }
    guard !stepped else { return }
    scrolled += delta
    guard abs(scrolled) >= Self.scrollStep else { return }
    stepped = true
    step(scrolled < 0 ? 1 : -1)
  }

  /// Steps `step` workspaces along this screen's chips, not past either end.
  private func step(_ step: Int) {
    guard let workspace = bar.state?.workspace(steppingBy: step, onScreen: index) else { return }
    bar.switchTo(workspace, onScreen: index)
  }

  // MARK: Drawing helpers

  private enum Fonts {
    static let bold = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    static let regular = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    static let small = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
  }

  private static func attributes(_ font: NSFont, _ color: NSColor, _ shadow: NSShadow?)
    -> [NSAttributedString.Key: Any]
  {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    var attributes: [NSAttributedString.Key: Any] = [
      .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
    ]
    if let shadow { attributes[.shadow] = shadow }
    return attributes
  }

  /// "+`count`", for a chip's apps whose icons did not fit; empty for none.
  private static func moreLabel(_ count: Int, _ ink: NSColor, _ shadow: NSShadow?)
    -> NSAttributedString
  {
    NSAttributedString(
      string: count > 0 ? "+\(count)" : "", attributes: attributes(Fonts.small, ink, shadow))
  }

  /// Draws `text` vertically centred in a view `height` high, from `x`, at most `maxWidth` wide.
  private static func drawText(
    _ text: NSAttributedString, x: CGFloat, maxWidth: CGFloat, height: CGFloat
  ) {
    guard maxWidth > 0 else { return }
    let size = text.size()
    text.draw(
      with: NSRect(
        x: x, y: ((height - size.height) / 2).rounded(), width: min(ceil(size.width), maxWidth),
        height: ceil(size.height)),
      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
  }

  private static func drawIcon(_ icon: NSImage, x: CGFloat, height: CGFloat, alpha: CGFloat) {
    icon.draw(
      in: NSRect(
        x: x, y: ((height - ChipLayout.iconSize) / 2).rounded(), width: ChipLayout.iconSize,
        height: ChipLayout.iconSize),
      from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true,
      hints: [.interpolation: NSImageInterpolation.high.rawValue])
  }

  private static func fillChip(_ chip: NSRect, _ color: NSColor) {
    color.setFill()
    NSBezierPath(
      roundedRect: chip, xRadius: ChipLayout.height / 2, yRadius: ChipLayout.height / 2
    ).fill()
  }

  private static func drawWithShadow(_ shadow: NSShadow?, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    shadow?.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
  }

  private static func symbol(_ name: String, level: Double?, ink: NSColor) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
      .applying(NSImage.SymbolConfiguration(paletteColors: [ink]))
    let image =
      if let level {
        NSImage(systemSymbolName: name, variableValue: level, accessibilityDescription: nil)
      } else {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
      }
    return image?.withSymbolConfiguration(configuration)
  }
}
