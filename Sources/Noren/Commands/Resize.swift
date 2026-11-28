// `noren resize ARROW [POINTS]`: the resize keys, moving the edge the arrow points at
// (NorenCore/EdgeResize) instead of AeroSpace's grow-or-shrink. Bind it in AeroSpace's config,
// for example `alt-ctrl-h = 'exec-and-forget noren resize left'`.
import CoreGraphics
import Foundation
import NorenCore

enum Resize {
  static let usage = "usage: noren resize left|right|up|down [POINTS]"

  static func run(_ arguments: [String]) -> Int32 {
    guard (1...2).contains(arguments.count), let arrow = ResizeArrow(rawValue: arguments[0]),
      let points = arguments.count == 2 ? Int(arguments[1]) : 20, points > 0
    else { return Commands.fail(usage, status: 2) }
    // The `aerospace` beside this noren, so the two always speak the same protocol
    let aerospace = URL(filePath: CommandLine.arguments[0]).resolvingSymlinksInPath()
      .deletingLastPathComponent().appending(path: "aerospace").path
    guard
      let focused = UInt32(
        output(aerospace, ["list-windows", "--focused", "--format", "%{window-id-native}"]) ?? ""),
      let listing = output(
        aerospace,
        [
          "list-windows", "--workspace", "focused", "--format",
          "%{window-id-native} %{window-parent-container-layout}",
        ])
    else { return Commands.fail("noren resize: AeroSpace has no focused window") }
    let tiled = listing.split(separator: "\n").compactMap { line -> UInt32? in
      let fields = line.split(separator: " ")
      guard fields.count == 2, fields[1].hasSuffix("_tiles") || fields[1].hasSuffix("_accordion")
      else { return nil }
      return UInt32(fields[0])
    }
    let frames = Self.frames(of: tiled + [focused])
    guard let frame = frames[focused] else {
      return Commands.fail("noren resize: the focused window is not on screen")
    }
    let resize = EdgeResize(
      arrow, by: points, focused: frame,
      others: tiled.filter { $0 != focused }.compactMap { frames[$0] })
    return output(aerospace, resize.arguments) == nil ? 1 : 0
  }

  /// The windows' frames as the window server has them, by id
  private static func frames(of windows: [UInt32]) -> [UInt32: CGRect] {
    let ids = windows.map { NSNumber(value: $0) } as CFArray
    guard let info = CGWindowListCreateDescriptionFromArray(ids) as? [[String: Any]] else {
      return [:]
    }
    var frames: [UInt32: CGRect] = [:]
    for window in info {
      guard let id = window[kCGWindowNumber as String] as? UInt32,
        let bounds = window[kCGWindowBounds as String] as? NSDictionary,
        let frame = CGRect(dictionaryRepresentation: bounds)
      else { continue }
      frames[id] = frame
    }
    return frames
  }

  /// What `executable` prints, trimmed, or nil when it fails
  private static func output(_ executable: String, _ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(filePath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    do {
      try process.run()
    } catch {
      return nil
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
