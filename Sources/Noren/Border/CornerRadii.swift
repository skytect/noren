// A window's corner radii as macOS rounds them (NorenCore's WindowCorners has the model), read
// cheaply enough to ask again each time the border is fitted.
//
// The window server's radius comes from private SkyLight calls, looked up at run time. The
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

/// The SkyLight calls that read the window server's corner radii.
private struct SkyLight {
  private typealias MainConnectionID = @convention(c) () -> Int32
  private typealias QueryWindows =
    @convention(c) (Int32, CFArray, UInt32) -> Unmanaged<
      AnyObject
    >?
  private typealias QueryResultCopyWindows = @convention(c) (AnyObject) -> Unmanaged<AnyObject>?
  private typealias IteratorAdvance = @convention(c) (AnyObject) -> Bool
  private typealias IteratorGetCornerRadii = @convention(c) (AnyObject) -> Unmanaged<CFArray>?

  private let mainConnection: MainConnectionID
  private let queryWindows: QueryWindows
  private let copyWindows: QueryResultCopyWindows
  private let advance: IteratorAdvance
  private let cornerRadii: IteratorGetCornerRadii

  /// The calls, or nil when SkyLight or one of them is missing, which is reported.
  static let shared = load()

  private static func load() -> SkyLight? {
    let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    guard let skyLight = dlopen(path, RTLD_LAZY) else {
      Problems.report("the border cannot load SkyLight: \(String(cString: dlerror()))")
      return nil
    }
    func symbol<T>(_ name: String, as type: T.Type) -> T? {
      guard let address = dlsym(skyLight, name) else {
        Problems.report("SkyLight has no \(name); the border's corners may not fit")
        return nil
      }
      return unsafeBitCast(address, to: type)
    }
    guard let mainConnection = symbol("SLSMainConnectionID", as: MainConnectionID.self),
      let queryWindows = symbol("SLSWindowQueryWindows", as: QueryWindows.self),
      let copyWindows = symbol("SLSWindowQueryResultCopyWindows", as: QueryResultCopyWindows.self),
      let advance = symbol("SLSWindowIteratorAdvance", as: IteratorAdvance.self),
      let cornerRadii = symbol("SLSWindowIteratorGetCornerRadii", as: IteratorGetCornerRadii.self)
    else { return nil }
    return SkyLight(
      mainConnection: mainConnection, queryWindows: queryWindows, copyWindows: copyWindows,
      advance: advance, cornerRadii: cornerRadii)
  }

  /// The window server's radius for `window` when it rounds all four corners alike, else 0.
  func radius(of window: CGWindowID) -> CGFloat {
    let windows = [NSNumber(value: window)] as CFArray
    guard let query = queryWindows(mainConnection(), windows, 0)?.takeRetainedValue(),
      let iterator = copyWindows(query)?.takeRetainedValue(), advance(iterator),
      let radii = cornerRadii(iterator)?.takeUnretainedValue() as? [NSNumber]
    else { return 0 }
    // Which corner each of the four is, is not known; only four alike are taken
    guard radii.count == 4, Set(radii).count == 1 else { return 0 }
    return CGFloat(radii[0].doubleValue)
  }
}
