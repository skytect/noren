// The one-shot commands, run as `noren COMMAND [ARGS]` instead of the app. None needs a privacy
// permission, so any copy of noren runs them.
//
//   noren sidecar               disconnects if an iPad is connected, otherwise connects the first
//                               one nearby as a second screen (Sidecar)
//   noren sidecar list          the iPads Sidecar can use, marking connected ones
//   noren lock                  locks the screen at once, as Lock Screen in the Apple menu does
//   noren lock check            only looks the lock function up (exit 0 when it is there)
//   noren display-mode          lists the sizes the built-in screen offers ("Looks like" in
//                               Displays settings), marking the current one
//   noren display-mode W H      changes to that size, in points (the sharpest mode of that size,
//                               at the highest refresh rate), and keeps it across restarts
//   noren resize ARROW [POINTS]  moves the edge between the focused window and its neighbour the
//                               way ARROW (left, right, up, down) points, by POINTS (20)
import Foundation

enum Commands {
  static let usage = """
    usage: noren                                    (the app)
           noren sidecar [list]
           noren lock [check]
           noren display-mode [WIDTH HEIGHT]
           noren resize left|right|up|down [POINTS]
    """

  /// Runs the command `name` with `arguments`, and returns its exit status.
  static func run(_ name: String, _ arguments: [String]) -> Int32 {
    switch name {
    case "sidecar": Sidecar.run(arguments)
    case "lock": Lock.run(arguments)
    case "display-mode": DisplayModeCommand.run(arguments)
    case "resize": Resize.run(arguments)
    default: fail(usage, status: 2)
    }
  }

  /// Prints `message` on stderr and returns `status`.
  static func fail(_ message: String, status: Int32 = 1) -> Int32 {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    return status
  }
}
