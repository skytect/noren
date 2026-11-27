// The private SkyLight calls noren reads windows with, looked up at run time: the window server's
// corner radii of a window (the border's corners), and its sublevel, its place among the windows
// of its level (Layers' Dock payload puts tiled windows at the backstop sublevel; noren may set its
// own windows').
import AppKit

/// The SkyLight calls that read windows.
struct SkyLight {
  private typealias MainConnectionID = @convention(c) () -> Int32
  private typealias QueryWindows =
    @convention(c) (Int32, CFArray, UInt32) -> Unmanaged<
      AnyObject
    >?
  private typealias QueryResultCopyWindows = @convention(c) (AnyObject) -> Unmanaged<AnyObject>?
  private typealias IteratorAdvance = @convention(c) (AnyObject) -> Bool
  private typealias IteratorGetCornerRadii = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
  private typealias GetWindowSubLevel = @convention(c) (Int32, UInt32) -> Int32
  private typealias SetWindowSubLevel = @convention(c) (Int32, UInt32, Int32) -> Int32

  private let mainConnection: MainConnectionID
  private let queryWindows: QueryWindows
  private let copyWindows: QueryResultCopyWindows
  private let advance: IteratorAdvance
  private let cornerRadii: IteratorGetCornerRadii
  private let getSubLevel: GetWindowSubLevel
  private let setSubLevel: SetWindowSubLevel

  /// The calls, or nil when SkyLight or one of them is missing, which is reported.
  static let shared = load()

  private static func load() -> SkyLight? {
    let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    guard let skyLight = dlopen(path, RTLD_LAZY) else {
      Problems.report("noren cannot load SkyLight: \(String(cString: dlerror()))")
      return nil
    }
    func symbol<T>(_ name: String, as type: T.Type) -> T? {
      guard let address = dlsym(skyLight, name) else {
        Problems.report("SkyLight has no \(name); the border's corners and level may not fit")
        return nil
      }
      return unsafeBitCast(address, to: type)
    }
    guard let mainConnection = symbol("SLSMainConnectionID", as: MainConnectionID.self),
      let queryWindows = symbol("SLSWindowQueryWindows", as: QueryWindows.self),
      let copyWindows = symbol("SLSWindowQueryResultCopyWindows", as: QueryResultCopyWindows.self),
      let advance = symbol("SLSWindowIteratorAdvance", as: IteratorAdvance.self),
      let cornerRadii = symbol("SLSWindowIteratorGetCornerRadii", as: IteratorGetCornerRadii.self),
      let getSubLevel = symbol("SLSGetWindowSubLevel", as: GetWindowSubLevel.self),
      let setSubLevel = symbol("SLSSetWindowSubLevel", as: SetWindowSubLevel.self)
    else { return nil }
    return SkyLight(
      mainConnection: mainConnection, queryWindows: queryWindows, copyWindows: copyWindows,
      advance: advance, cornerRadii: cornerRadii, getSubLevel: getSubLevel,
      setSubLevel: setSubLevel)
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

  /// The sublevel the Dock payload puts tiled windows at, under the others of the normal level
  static let below = CGWindowLevelForKey(.backstopMenu)

  /// Whether `window` sits under the other windows of its level, where the Dock payload puts
  /// tiled windows
  func isBelow(_ window: CGWindowID) -> Bool {
    getSubLevel(mainConnection(), window) < 0
  }

  /// Puts `window`, one of noren's own, at `subLevel` among the windows of its level
  func setSubLevel(_ subLevel: Int32, of window: CGWindowID) {
    _ = setSubLevel(mainConnection(), window, subLevel)
  }
}
