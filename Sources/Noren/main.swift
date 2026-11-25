// noren: an app that draws a bar, a workspace strip and a window border around the AeroSpace
// window manager (README.md). It runs in the background, with no Dock icon or menu bar of its own.
import AppKit

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
