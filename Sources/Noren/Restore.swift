// Brings the apps back after a restart or a logout as they were: the same apps running, each
// window on its workspace, and no window more. It is meant to replace macOS's own relaunch, which
// should be off: that reopens every app at once, each with a fresh window wherever AeroSpace puts
// it.
//
// While noren runs it keeps a snapshot (RestoreSnapshot) in
// ~/Library/Application Support/noren/snapshot.json: the regular apps from an Applications
// folder, windows or none, and each window's AeroSpace workspace and title. It is taken again
// shortly after any AeroSpace event and any app launch or quit. When macOS announces a logout,
// restart or shutdown, one last snapshot is marked as the session's end and kept from then on, so
// the apps quitting one by one do not empty it.
//
// The snapshot is restored when noren starts after that mark, or in a new boot (a crash or power
// loss leaves no mark). Once AeroSpace is connected, each app in it that is not running already
// is launched hidden and without activation. Its windows are left to open, then after `settle`
// without a new one (`launchWait` for the first) the app's windows are matched to the recorded
// ones by title (TitleMatching) and moved to their workspaces; a window left over is closed with
// its close button, through Accessibility. Then the app is shown again. Apps not in the snapshot,
// or started before noren got to them, are never touched, nor is a window that opens after its
// app has settled.
import AppKit
import NorenCore
import NorenPrivate
import os

final class Restore: Part {
  /// An app from the snapshot while it is brought back.
  private final class RestoringApp {
    let bundleId: String
    let windows: [RestoreSnapshot.Window]
    /// Once launched
    var running: NSRunningApplication?
    /// Which settle timer counts
    var generation = 0
    var settling = false

    init(_ app: RestoreSnapshot.App) {
      bundleId = app.bundleId
      windows = app.windows
    }
  }

  private let log = Logger(subsystem: "local.noren", category: "restore")
  private let aeroSpace: AeroSpaceClient

  /// How long after an event the snapshot is taken, so a burst of events costs one
  private let snapshotDelay = Duration.seconds(1)
  /// How long a launched app has to open its first window, and then each next one
  private let launchWait = Duration.seconds(30)
  private let settle = Duration.seconds(3)
  /// A logout or shutdown that has not ended noren by then was cancelled: snapshots resume
  private let cancelledEnd: TimeInterval = 300

  /// The latest snapshot saved or placement made; each waits for the one before, so they run in
  /// the order they were asked for
  private var following: Task<Void, Never>?
  /// The latest snapshot taken
  private var last: RestoreSnapshot?
  /// The apps being brought back, by bundle id
  private var restoring: [String: RestoringApp] = [:]
  private var launched = false
  private var snapshotPending = false
  /// When macOS announced the session's end
  private var ending: Date?

  private static let snapshotURL = URL.applicationSupportDirectory
    .appending(components: "noren", "snapshot.json")

  init(aeroSpace: AeroSpaceClient) {
    self.aeroSpace = aeroSpace
  }

  func start() {
    plan()
    let center = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
    ] {
      _ = center.addObserver(forName: name, object: nil, queue: .main) { [unowned self] _ in
        MainActor.assumeIsolated { scheduleSnapshot() }
      }
    }
    _ = center.addObserver(
      forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
    ) { [unowned self] _ in
      MainActor.assumeIsolated {
        ending = Date()
        save(apps: regularApps(), ending: true)
      }
    }
  }

  func handle(_ event: AeroSpaceEvent) {
    switch event {
    case .connected where !launched:
      launched = true
      for app in restoring.values { launch(app) }
      if restoring.isEmpty { scheduleSnapshot() }
    case .windowDetected(_, _, let appBundleId?, _):
      if launched, let app = restoring[appBundleId], !app.settling {
        scheduleSettle(app, after: settle)
      }
    default:
      break
    }
    scheduleSnapshot()
  }

  // MARK: The snapshot

  /// This boot's id, new at each boot
  private static func bootSession() -> String {
    var uuid = [CChar](repeating: 0, count: 64)
    var size = uuid.count
    guard sysctlbyname("kern.bootsessionuuid", &uuid, &size, nil, 0) == 0 else { return "" }
    return String(decoding: uuid.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }

  /// The bundle ids of the regular apps from an Applications folder, noren aside
  private func regularApps() -> [String] {
    var apps: [String] = []
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
      guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
        app.bundleURL?.path.contains("/Applications/") == true, !apps.contains(id)
      else { continue }
      apps.append(id)
    }
    return apps
  }

  private var isEnding: Bool {
    guard let ending else { return false }
    return -ending.timeIntervalSinceNow < cancelledEnd
  }

  /// Takes a snapshot shortly, unless apps are being brought back or the session is ending
  private func scheduleSnapshot() {
    guard !snapshotPending, restoring.isEmpty, !isEnding else { return }
    snapshotPending = true
    Task {
      try? await Task.sleep(for: snapshotDelay)
      snapshotPending = false
      guard restoring.isEmpty, !isEnding else { return }
      save(apps: regularApps(), ending: false)
    }
  }

  /// Takes the snapshot of `apps` and saves it; `ending` marks it as the session's end, from the
  /// last one taken if AeroSpace no longer answers.
  private func save(apps: [String], ending: Bool) {
    following = Task { [previous = following] in
      await previous?.value
      let windows: [ListedWindow]?
      do {
        windows = try await aeroSpace.run(
          ["list-windows", "--all", "--json", "--format", ListedWindow.format],
          as: [ListedWindow].self)
      } catch {
        log.error("could not list the windows: \(error, privacy: .public)")
        windows = nil
      }
      if let windows {
        last = RestoreSnapshot(
          boot: Self.bootSession(), apps: apps,
          windows: windows.map {
            (appId: $0.bundleId, window: .init(workspace: $0.workspace, title: $0.title))
          })
      }
      guard var snapshot = last, windows != nil || ending else { return }
      snapshot.ending = ending
      write(snapshot)
      if ending {
        log.info("the session is ending: snapshot of \(snapshot.apps.count) apps kept")
      }
    }
  }

  private func write(_ snapshot: RestoreSnapshot) {
    do {
      try FileManager.default.createDirectory(
        at: Self.snapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try snapshot.json().write(to: Self.snapshotURL, options: .atomic)
    } catch {
      log.error("could not save the snapshot: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: Bringing the apps back

  /// The apps to bring back from the saved snapshot, if it ended a session or an earlier boot
  private func plan() {
    guard let data = try? Data(contentsOf: Self.snapshotURL) else { return }
    let snapshot: RestoreSnapshot
    do {
      snapshot = try RestoreSnapshot(json: data)
    } catch {
      log.error("could not read the snapshot: \(error, privacy: .public)")
      return
    }
    guard snapshot.isRestored(inBoot: Self.bootSession()) else { return }
    for app in snapshot.apps { restoring[app.bundleId] = RestoringApp(app) }
    let from = snapshot.ending ? "session's end" : "last boot"
    log.info("restoring \(self.restoring.count) apps from the \(from, privacy: .public)")
  }

  private func launch(_ app: RestoringApp) {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleId).isEmpty
    else {
      restoring[app.bundleId] = nil
      log.info("not restoring \(app.bundleId, privacy: .public): already running")
      return
    }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) else {
      restoring[app.bundleId] = nil
      log.info("not restoring \(app.bundleId, privacy: .public): not installed")
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.hides = true
    configuration.addsToRecentItems = false
    Task {
      do {
        app.running = try await NSWorkspace.shared.openApplication(
          at: url, configuration: configuration)
      } catch {
        log.error(
          "could not launch \(app.bundleId, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
        if restoring[app.bundleId] === app { restoring[app.bundleId] = nil }
        if restoring.isEmpty { scheduleSnapshot() }
      }
    }
    scheduleSettle(app, after: launchWait)
  }

  /// Places the app's windows once `delay` passes without a new one
  private func scheduleSettle(_ app: RestoringApp, after delay: Duration) {
    app.generation += 1
    let generation = app.generation
    Task {
      try? await Task.sleep(for: delay)
      guard app.generation == generation, !app.settling, restoring[app.bundleId] === app else {
        return
      }
      guard let running = app.running else {  // still launching
        scheduleSettle(app, after: settle)
        return
      }
      app.settling = true
      place(app, pid: running.processIdentifier)
    }
  }

  /// Puts the app's windows on their recorded workspaces and closes the ones left over
  private func place(_ app: RestoringApp, pid: pid_t) {
    following = Task { [previous = following] in
      await previous?.value
      let all: [ListedWindow]
      do {
        all = try await aeroSpace.run(
          ["list-windows", "--all", "--json", "--format", ListedWindow.format],
          as: [ListedWindow].self)
      } catch {
        log.error("could not list the windows: \(error, privacy: .public)")
        app.settling = false
        scheduleSettle(app, after: settle)
        return
      }
      let windows = all.filter { $0.pid == pid }
      let recorded = app.windows
      let matching = TitleMatching(
        windows: windows.map(\.title), recorded: recorded.map(\.title))
      var done: [String] = []
      for pair in matching.pairs {
        let window = windows[pair.window]
        let workspace = recorded[pair.recorded].workspace
        if window.workspace == workspace {
          done.append("\"\(window.title)\" stays on \(workspace)")
          continue
        }
        do {
          _ = try await aeroSpace.run(
            ["move-node-to-workspace", "--window-id", String(window.id), "--", workspace])
          done.append("\"\(window.title)\" to \(workspace)")
        } catch {
          done.append("\"\(window.title)\" not moved to \(workspace)")
        }
      }
      for index in matching.unmatchedWindows {
        let window = windows[index]
        guard let nativeId = window.nativeId else {
          done.append("\"\(window.title)\" not closed: AeroSpace lost its id")
          continue
        }
        let closed = await Self.closeWindow(nativeId, of: pid)
        done.append("\"\(window.title)\"" + (closed ? " closed" : " not closed"))
      }
      if !matching.unmatchedRecorded.isEmpty {
        done.append("\(matching.unmatchedRecorded.count) recorded windows did not open")
      }
      finish(app, summary: done.isEmpty ? "no windows" : done.joined(separator: ", "))
    }
  }

  /// Presses the close button of the window `native` (a window server id) of the app `pid`. Off
  /// the main thread: Accessibility waits on the app, which may be slow to answer.
  @concurrent
  private nonisolated static func closeWindow(_ native: CGWindowID, of pid: pid_t) async -> Bool {
    let app = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
      let windows = value as? [AXUIElement]
    else { return false }
    for window in windows {
      var found: CGWindowID = 0
      guard _AXUIElementGetWindow(window, &found) == .success, found == native else { continue }
      var button: CFTypeRef?
      guard
        AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &button)
          == .success, let button, CFGetTypeID(button) == AXUIElementGetTypeID()
      else { return false }
      return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        == .success
    }
    return false
  }

  /// The app is done: shown again, and once the last is, snapshots resume
  private func finish(_ app: RestoringApp, summary: String) {
    guard restoring[app.bundleId] === app else { return }
    restoring[app.bundleId] = nil
    app.running?.unhide()
    // The summary holds window titles, which may be personal: redacted unless the log is told
    // otherwise
    log.info("restored \(app.bundleId, privacy: .public): \(summary, privacy: .private)")
    guard restoring.isEmpty else { return }
    log.info("restore done")
    scheduleSnapshot()
  }
}
