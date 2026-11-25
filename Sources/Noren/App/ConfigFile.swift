import Foundation
import NorenCore

/// noren's config file: $XDG_CONFIG_HOME/noren/noren.toml, ~/.config/noren/noren.toml without
/// XDG_CONFIG_HOME. A missing file is an empty config: every part on, with its defaults.
enum ConfigFile {
  static var directory: URL {
    let base =
      ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
      ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config")
    return base.appending(path: "noren")
  }

  static var url: URL { directory.appending(path: "noren.toml") }

  /// The file's text, or nil when there is no file.
  static func text() throws -> String? {
    do {
      return try String(contentsOf: url, encoding: .utf8)
    } catch CocoaError.fileReadNoSuchFile {
      return nil
    }
  }

  /// The config `text` holds, nil meaning no file.
  static func config(_ text: String?) throws(ConfigError) -> Config {
    guard let text else { return Config() }
    return try Config(toml: text)
  }
}

/// Calls back whenever the config file may have changed: written in place (`>>`, most editors'
/// plain save), or replaced (an atomic save, home-manager's new symlink), which only its directory
/// sees.
final class ConfigWatcher {
  private let onChange: @MainActor () -> Void
  private var directory: (any DispatchSourceFileSystemObject)?
  private var file: (any DispatchSourceFileSystemObject)?

  init(onChange: @escaping @MainActor () -> Void) throws {
    self.onChange = onChange
    try FileManager.default.createDirectory(
      at: ConfigFile.directory, withIntermediateDirectories: true)
    directory = try watch(ConfigFile.directory.path, [.write])
    watchFile()
  }

  /// Watches the file now at the config's path, if there is one, in place of the one before.
  private func watchFile() {
    file?.cancel()
    file = nil
    do {
      file = try watch(ConfigFile.url.path, [.write, .extend, .delete, .rename])
    } catch POSIXError.ENOENT {
      // No file to watch; the directory sees one arrive
    } catch {
      Problems.report("noren cannot follow changes to \(ConfigFile.url.path): \(error)")
    }
  }

  private func watch(_ path: String, _ events: DispatchSource.FileSystemEvent) throws
    -> any DispatchSourceFileSystemObject
  {
    let descriptor = open(path, O_EVTONLY)
    guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor, eventMask: events, queue: .main)
    source.setEventHandler { [unowned self] in
      MainActor.assumeIsolated {
        watchFile()
        onChange()
      }
    }
    source.setCancelHandler { close(descriptor) }
    source.resume()
    return source
  }
}
