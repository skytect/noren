// The cursor theme: noren's own cursors in place of the system's, in every app. They are drawn at
// build time (assets/cursors/make.py) into Contents/Resources/Cursors: a PNG for each scale, frames
// stacked top to bottom, and cursors.json naming the system cursors each one replaces. Before a
// system cursor is first replaced, its images are copied into the window server under a noren
// name; turned off, noren puts those copies back. macOS keeps no other way back to its own arrow
// and I-beam while the window server runs: removing a replacement fails, and the system's images
// read back as the replacement. The copies and the replacements both last until logout.
import AppKit
import NorenCore
import os

final class Cursors: Part {
  private let log = Logger(subsystem: "local.noren", category: "cursors")
  private let enable: Bool

  init(config: PartConfig) {
    enable = config.enable
  }

  func start() {
    guard let server = CursorServer.load() else { return }
    if enable {
      apply(on: server)
    } else {
      putBack(on: server)
    }
  }

  private func apply(on server: CursorServer) {
    guard let theme = Self.theme() else { return }
    var missed: [String] = []
    for cursor in theme {
      for name in cursor.replaces {
        if server.images(of: original(name)) == nil, let system = server.images(of: name) {
          _ = server.register(system, as: original(name))
        }
        // Read back: macOS ignores some names without saying so
        guard server.register(cursor.images, as: name),
          server.images(of: name)?.hotspot == cursor.images.hotspot
        else {
          missed.append(name)
          continue
        }
      }
    }
    if missed.isEmpty {
      log.info("\(theme.count) cursors in place")
    } else {
      Problems.report("macOS did not take noren's cursors for \(missed.joined(separator: ", "))")
    }
  }

  private func putBack(on server: CursorServer) {
    guard let theme = Self.theme() else { return }
    var restored = 0
    for name in theme.flatMap(\.replaces) {
      guard let system = server.images(of: original(name)) else { continue }
      if server.register(system, as: name) {
        server.remove(original(name))
        restored += 1
      }
    }
    if restored > 0 { log.info("put back \(restored) of the system's cursors") }
  }

  private func original(_ name: String) -> String { "local.noren.original.\(name)" }

  /// One cursor of the theme: its images and the system cursors it replaces
  private struct ThemeCursor {
    var images: CursorImages
    var replaces: [String]
  }

  /// The theme in the app bundle, or nil, reported, when it cannot be read
  private static func theme() -> [ThemeCursor]? {
    guard let folder = Bundle.main.resourceURL?.appending(path: "Cursors") else { return nil }
    do {
      let manifest = try JSONDecoder().decode(
        CursorManifest.self, from: Data(contentsOf: folder.appending(path: "cursors.json")))
      return try manifest.cursors.map { cursor in
        let images = try manifest.scales.map { scale in
          let url = folder.appending(path: "\(cursor.file)@\(scale)x.png")
          guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
          else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url]) }
          return image
        }
        return ThemeCursor(
          images: CursorImages(
            size: CGSize(width: manifest.size, height: manifest.size),
            hotspot: CGPoint(x: cursor.hotspot[0], y: cursor.hotspot[1]),
            frames: cursor.frames, frameSeconds: cursor.frameSeconds, images: images),
          replaces: cursor.replaces)
      }
    } catch {
      Problems.report("noren could not read its cursors: \(error)")
      return nil
    }
  }
}

/// cursors.json, as make.py writes it
private struct CursorManifest: Decodable {
  struct Cursor: Decodable {
    var file: String
    var replaces: [String]
    var hotspot: [Double]
    var frames: Int
    var frameSeconds: Double
  }

  /// Points a side
  var size: Double
  var scales: [Int]
  var cursors: [Cursor]
}

/// A registered cursor: one image for each scale, each with the frames top to bottom
private struct CursorImages {
  var size: CGSize
  var hotspot: CGPoint
  var frames: Int
  var frameSeconds: Double
  var images: [CGImage]
}

/// The window server's named cursors, through SkyLight's private calls looked up at run time
private struct CursorServer {
  private typealias MainConnectionID = @convention(c) () -> Int32
  private typealias Register =
    @convention(c) (
      Int32, UnsafePointer<CChar>, Bool, Bool, CGSize, CGPoint, Int, CGFloat, CFArray,
      UnsafeMutablePointer<Int32>
    ) -> Int32
  private typealias CopyImages =
    @convention(c) (
      Int32, UnsafePointer<CChar>, UnsafeMutablePointer<CGSize>, UnsafeMutablePointer<CGPoint>,
      UnsafeMutablePointer<Int>, UnsafeMutablePointer<CGFloat>,
      UnsafeMutablePointer<Unmanaged<CFArray>?>
    ) -> Int32
  private typealias Remove = @convention(c) (Int32, UnsafePointer<CChar>, Bool) -> Int32

  private let connection: Int32
  private let registerCall: Register
  private let copyImages: CopyImages
  private let removeCall: Remove

  static func load() -> CursorServer? {
    let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    guard let skyLight = dlopen(path, RTLD_LAZY),
      let main = dlsym(skyLight, "SLSMainConnectionID"),
      let register = dlsym(skyLight, "SLSRegisterCursorWithImages"),
      let copy = dlsym(skyLight, "SLSCopyRegisteredCursorImages"),
      let remove = dlsym(skyLight, "SLSRemoveRegisteredCursor")
    else {
      Problems.report("SkyLight has no calls for named cursors; noren's cursors are off")
      return nil
    }
    return CursorServer(
      connection: unsafeBitCast(main, to: MainConnectionID.self)(),
      registerCall: unsafeBitCast(register, to: Register.self),
      copyImages: unsafeBitCast(copy, to: CopyImages.self),
      removeCall: unsafeBitCast(remove, to: Remove.self))
  }

  /// The images registered as `name`, or nil when there are none
  func images(of name: String) -> CursorImages? {
    var size = CGSize.zero
    var hotspot = CGPoint.zero
    var frames = 0
    var frameSeconds: CGFloat = 0
    var images: Unmanaged<CFArray>?
    guard copyImages(connection, name, &size, &hotspot, &frames, &frameSeconds, &images) == 0,
      let images = images?.takeRetainedValue() as? [CGImage], !images.isEmpty
    else { return nil }
    return CursorImages(
      size: size, hotspot: hotspot, frames: frames, frameSeconds: frameSeconds, images: images)
  }

  /// Registers `cursor` as `name` for every app, at once; whether the window server took it
  func register(_ cursor: CursorImages, as name: String) -> Bool {
    var seed: Int32 = 0
    return registerCall(
      connection, name, true, true, cursor.size, cursor.hotspot, cursor.frames,
      cursor.frameSeconds, cursor.images as CFArray, &seed) == 0
  }

  func remove(_ name: String) {
    _ = removeCall(connection, name, false)
  }
}
