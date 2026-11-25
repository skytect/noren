// `noren lock`: SACLockScreenImmediate from the private login framework, the function behind the
// Apple menu's Lock Screen. Sending its shortcut through System Events instead would need
// Accessibility.
import Foundation

enum Lock {
  private typealias LockScreen = @convention(c) () -> Int32

  static func run(_ arguments: [String]) -> Int32 {
    guard arguments == [] || arguments == ["check"] else {
      return Commands.fail("usage: noren lock [check]", status: 2)
    }
    guard
      let login = dlopen(
        "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY)
    else {
      return Commands.fail("lock: cannot load the login framework: \(String(cString: dlerror()))")
    }
    guard let symbol = dlsym(login, "SACLockScreenImmediate") else {
      return Commands.fail("lock: SACLockScreenImmediate not found")
    }
    if arguments == ["check"] {
      print("lock: SACLockScreenImmediate found")
      return 0
    }
    return unsafeBitCast(symbol, to: LockScreen.self)()
  }
}
