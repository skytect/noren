import Foundation
import NorenCore
import Testing

@Suite struct RestoreSnapshotTests {
  @Test func `a snapshot in the format the first noren wrote decodes`() throws {
    let json = """
      {"boot":"0D3C61F2-5B0A-4C8E-9E11-3A2B7C4D5E6F","apps":[{"windows":[],"bundleId":\
      "com.example.notes"},{"windows":[{"title":"Inbox","workspace":"1"},{"title":"Draft: hello",\
      "workspace":"6"}],"bundleId":"com.example.mail"}],"ending":false}
      """

    let snapshot = try RestoreSnapshot(json: Data(json.utf8))

    #expect(
      snapshot
        == RestoreSnapshot(
          boot: "0D3C61F2-5B0A-4C8E-9E11-3A2B7C4D5E6F",
          apps: [
            .init(bundleId: "com.example.notes", windows: []),
            .init(
              bundleId: "com.example.mail",
              windows: [
                .init(workspace: "1", title: "Inbox"), .init(workspace: "6", title: "Draft: hello"),
              ]),
          ],
          ending: false))
  }

  @Test func `a snapshot is saved with the same keys it is read with`() throws {
    let snapshot = RestoreSnapshot(
      boot: "B",
      apps: [.init(bundleId: "com.example.mail", windows: [.init(workspace: "2", title: "Inbox")])],
      ending: true)

    #expect(
      String(decoding: try snapshot.json(), as: UTF8.self)
        == #"{"apps":[{"bundleId":"com.example.mail","windows":[{"title":"Inbox","workspace":"2"}]}],"boot":"B","ending":true}"#
    )
  }

  @Test func `a snapshot holds the apps given, each with only its own windows`() {
    let snapshot = RestoreSnapshot(
      boot: "B", apps: ["com.example.mail", "com.example.notes"],
      windows: [
        (appId: "com.example.browser", window: .init(workspace: "1", title: "News")),
        (appId: "com.example.mail", window: .init(workspace: "2", title: "Inbox")),
        (appId: nil, window: .init(workspace: "3", title: "Untitled")),
        (appId: "com.example.mail", window: .init(workspace: "4", title: "Sent")),
      ])

    #expect(
      snapshot.apps == [
        .init(
          bundleId: "com.example.mail",
          windows: [.init(workspace: "2", title: "Inbox"), .init(workspace: "4", title: "Sent")]),
        .init(bundleId: "com.example.notes", windows: []),
      ])
  }

  @Test func `a snapshot that ended the session is restored in the same boot`() {
    let snapshot = RestoreSnapshot(boot: "B1", apps: [], ending: true)

    #expect(snapshot.isRestored(inBoot: "B1"))
  }

  @Test func `a snapshot from this boot that did not end the session is not restored`() {
    let snapshot = RestoreSnapshot(boot: "B1", apps: [], ending: false)

    #expect(!snapshot.isRestored(inBoot: "B1"))
  }

  @Test func `a snapshot from an earlier boot is restored without an end mark`() {
    let snapshot = RestoreSnapshot(boot: "B1", apps: [], ending: false)

    #expect(snapshot.isRestored(inBoot: "B2"))
  }
}
