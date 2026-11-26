// A dynamic wallpaper's frames by the time of day. macOS reads the schedule from the first image of
// the wallpaper's HEIC file, as the XMP tag apple_desktop:h24: a base64 binary property list,
// {ti: [{t: when the frame starts, as a fraction of the day, i: the frame's image index}]}.
import Foundation

/// The frames of a wallpaper that changes with the time of day, each from its start until the
/// next frame's. Times are fractions of the day since midnight, 0 up to 1.
public struct WallpaperSchedule: Equatable, Sendable {
  public struct Change: Equatable, Sendable {
    public let start: Double
    public let frame: Int
  }

  /// In order of start; never empty
  public let changes: [Change]

  /// The schedule in an apple_desktop:h24 tag's value, or nil when it holds none.
  public init?(h24 value: String) {
    guard let data = Data(base64Encoded: value),
      let list = try? PropertyListDecoder().decode(List.self, from: data),
      !list.ti.isEmpty
    else { return nil }
    changes = list.ti.map { Change(start: $0.t, frame: $0.i) }.sorted { $0.start < $1.start }
  }

  /// The frame shown at `time`: the last to start by then, or before the day's first start,
  /// the frame left from the evening before.
  public func frame(at time: Double) -> Int {
    (changes.last { $0.start <= time } ?? changes[changes.count - 1]).frame
  }

  /// When the frame shown at `time` gives way to the next: past 1 when that is tomorrow.
  public func nextChange(after time: Double) -> Double {
    changes.first { $0.start > time }?.start ?? changes[0].start + 1
  }

  private struct List: Decodable {
    struct Time: Decodable {
      let t: Double
      let i: Int
    }
    let ti: [Time]
  }
}
