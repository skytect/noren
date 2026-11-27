// A window's corner radii as macOS rounds them (NorenCore's WindowCorners has the model), read
// cheaply enough to ask again each time the border is fitted.
//
// The window server's radius comes from SkyLight (Shared/SkyLight.swift). The
// standard window's radius is AppKit's private _cornerRadius of an unshown window of noren's own
// (16 points on macOS 27), and a screen's is NSScreen's private _cornerRadius.
import AppKit
import NorenCore
import os

enum CornerRadii {
  /// `window`'s corner radii with its frame at `frame`, in Cocoa coordinates.
  static func of(_ window: CGWindowID, frame: CGRect) -> WindowCorners {
    if let radius = SkyLight.shared?.radius(of: window), radius > 0 {
      return WindowCorners(all: radius)
    }
    let screens = NSScreen.screens
    guard let index = frame.indexOfLargestOverlap(in: screens.map(\.frame)) else {
      return WindowCorners(all: standardRadius)
    }
    return WindowCorners(
      frame: frame, radius: standardRadius, screen: screens[index].frame,
      screenRadius: privateCornerRadius(of: screens[index]))
  }

  /// The radius AppKit gives a standard titled window.
  private static let standardRadius: CGFloat = {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: .titled,
      backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    return privateCornerRadius(of: window)
  }()

  private typealias CornerRadiusCall = @convention(c) (AnyObject, Selector) -> CGFloat
  private static var reportedMissingCornerRadius = Set<String>()

  /// AppKit's private _cornerRadius of `object` (an NSWindow or an NSScreen), or 0 if it has none,
  /// which is reported once for each class.
  private static func privateCornerRadius(of object: NSObject) -> CGFloat {
    let selector = NSSelectorFromString("_cornerRadius")
    guard object.responds(to: selector) else {
      let name = String(describing: type(of: object))
      if reportedMissingCornerRadius.insert(name).inserted {
        Problems.report("\(name) has no _cornerRadius; the border's corners may not fit")
      }
      return 0
    }
    return unsafeBitCast(object.method(for: selector), to: CornerRadiusCall.self)(object, selector)
  }
}
