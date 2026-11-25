// Which of an app's windows, opened afresh, is which of the windows it had before, by title.
import Foundation

/// The windows paired with recorded windows by title: the most alike pair first, until the
/// windows or the recorded ones run out. Titles are alike most when they are the same, else by
/// the number of words they share (letters and digits, ignoring case); among equally alike pairs,
/// the earliest window and then the earliest recorded one go first. Windows with nothing in
/// common still pair, in order.
public struct TitleMatching: Equatable, Sendable {
  /// A window and the recorded window it is taken for, as indices into the titles given.
  public struct Pair: Equatable, Sendable {
    public let window: Int
    public let recorded: Int

    public init(window: Int, recorded: Int) {
      self.window = window
      self.recorded = recorded
    }
  }

  /// In the order they were made, the most alike first.
  public let pairs: [Pair]
  /// The windows left over, in order: more opened than were recorded.
  public let unmatchedWindows: [Int]
  /// The recorded windows left over, in order: fewer opened.
  public let unmatchedRecorded: [Int]

  public init(windows: [String], recorded: [String]) {
    var freeWindows = Array(windows.indices)
    var freeRecorded = Array(recorded.indices)
    let windowWords = windows.map(Self.words)
    let recordedWords = recorded.map(Self.words)
    func likeness(_ w: Int, _ r: Int) -> Int {
      windows[w] == recorded[r] ? .max : windowWords[w].intersection(recordedWords[r]).count
    }
    var pairs: [Pair] = []
    while let firstWindow = freeWindows.first, let firstRecorded = freeRecorded.first {
      var best = (window: firstWindow, recorded: firstRecorded, likeness: 0)
      for w in freeWindows {
        for r in freeRecorded where likeness(w, r) > best.likeness {
          best = (w, r, likeness(w, r))
        }
      }
      freeWindows.removeAll { $0 == best.window }
      freeRecorded.removeAll { $0 == best.recorded }
      pairs.append(Pair(window: best.window, recorded: best.recorded))
    }
    self.pairs = pairs
    unmatchedWindows = freeWindows
    unmatchedRecorded = freeRecorded
  }

  private static func words(_ title: String) -> Set<String> {
    Set(
      title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty })
  }
}
