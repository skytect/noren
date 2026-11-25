// noren: an app that draws a bar, a workspace strip and a window border around the AeroSpace
// window manager (README.md). It runs in the background, with no Dock icon or menu bar of its
// own. With a command as its first argument it runs that instead (Commands).
import Foundation

let arguments = CommandLine.arguments.dropFirst()
if let command = arguments.first {
  exit(Commands.run(command, Array(arguments.dropFirst())))
}
NorenApp().run()
