import Foundation
import NorenCore
import Testing

@Suite struct AeroSpaceListingTests {
  /// A window as `aerospace list-windows --all --json --format ListedWindow.format` prints it
  let window = """
    {
      "app-bundle-id" : "com.example.terminal",
      "app-name" : "Terminal",
      "app-pid" : 958,
      "window-id" : 16,
      "window-id-native" : 208,
      "window-parent-container-layout" : "h_tiles",
      "window-title" : "a | title",
      "workspace" : "1"
    }
    """

  /// Two workspaces as `aerospace list-workspaces --monitor all --json --format
  /// ListedWorkspace.format` prints them
  let workspaces = """
    [
      {
        "monitor-appkit-nsscreen-screens-id" : 1,
        "workspace" : "1",
        "workspace-is-focused" : true,
        "workspace-is-visible" : true
      },
      {
        "monitor-appkit-nsscreen-screens-id" : 2,
        "workspace" : "2",
        "workspace-is-focused" : false,
        "workspace-is-visible" : true
      }
    ]
    """

  /// The interpolation variables `format` asks AeroSpace for
  func variables(_ format: String) -> Set<String> {
    Set(format.matches(of: /%\{([a-z-]+)\}/).map { String($0.output.1) })
  }

  /// The keys of the JSON object `json`
  func keys(_ json: String) throws -> Set<String> {
    let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
    return Set(try #require(object as? [String: Any]).keys)
  }

  func listed(_ json: String) throws -> [ListedWindow] {
    try JSONDecoder().decode([ListedWindow].self, from: Data("[\(json)]".utf8))
  }

  /// `window` with its bundle id's line replaced by `line`
  func window(bundleIdLine line: String) -> String {
    window.replacing(#""app-bundle-id" : "com.example.terminal","#, with: line)
  }

  @Test func `the window format asks for exactly the fields AeroSpace's listing gives`() throws {
    #expect(variables(ListedWindow.format) == (try keys(window)))
  }

  @Test func `the workspace format asks for exactly the fields AeroSpace's listing gives`() throws {
    let first = try #require(workspaces.firstRange(of: "{")).lowerBound
    let end = try #require(workspaces.firstRange(of: "}")).upperBound

    #expect(variables(ListedWorkspace.format) == (try keys(String(workspaces[first..<end]))))
  }

  @Test func `a window listing decodes`() throws {
    #expect(
      try listed(window) == [
        ListedWindow(
          id: 16, nativeId: 208, layout: "h_tiles", workspace: "1", pid: 958,
          bundleId: "com.example.terminal", appName: "Terminal", title: "a | title")
      ])
  }

  @Test(arguments: [
    #""app-bundle-id" : "NULL-APP-BUNDLE-ID","#,
    #""app-bundle-id" : null,"#,
    "",
  ])
  func `an app without a bundle id decodes with none`(line: String) throws {
    #expect(try listed(window(bundleIdLine: line)).map(\.bundleId) == [nil])
  }

  @Test func `a window listing without a field AeroSpace always gives does not decode`() {
    let withoutLayout = window.replacing(
      #""window-parent-container-layout" : "h_tiles","#, with: "")

    #expect(throws: DecodingError.self) { try listed(withoutLayout) }
  }

  @Test func `a workspace listing decodes`() throws {
    #expect(
      try JSONDecoder().decode([ListedWorkspace].self, from: Data(workspaces.utf8)) == [
        ListedWorkspace(name: "1", monitorId: 1, isVisible: true, isFocused: true),
        ListedWorkspace(name: "2", monitorId: 2, isVisible: true, isFocused: false),
      ])
  }
}
