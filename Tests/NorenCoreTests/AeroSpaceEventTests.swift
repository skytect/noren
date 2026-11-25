import Foundation
import NorenCore
import Testing

@Suite struct AeroSpaceEventTests {
  @Test func `a focus change with a window`() throws {
    let event = try AeroSpaceEvent(
      json: Data(#"{"_event":"focus-changed","windowId":42,"workspace":"3"}"#.utf8))

    #expect(event == .focusChanged(windowId: 42, workspace: "3"))
  }

  @Test func `a focus change onto an empty workspace has no window`() throws {
    let event = try AeroSpaceEvent(json: Data(#"{"_event":"focus-changed","workspace":"5"}"#.utf8))

    #expect(event == .focusChanged(windowId: nil, workspace: "5"))
  }

  @Test func `a workspace change carries the one left`() throws {
    let json = #"{"_event":"focused-workspace-changed","workspace":"2","prevWorkspace":"1"}"#

    #expect(
      try AeroSpaceEvent(json: Data(json.utf8))
        == .focusedWorkspaceChanged(workspace: "2", previous: "1"))
  }

  @Test func `a detected window carries its app`() throws {
    let json = #"""
      {"_event":"window-detected","windowId":7,"workspace":"1","appBundleId":"com.example.editor","appName":"Editor"}
      """#

    #expect(
      try AeroSpaceEvent(json: Data(json.utf8))
        == .windowDetected(
          windowId: 7, workspace: "1", appBundleId: "com.example.editor", appName: "Editor"))
  }

  @Test func `a binding carries its mode and keys`() throws {
    let json = #"{"_event":"binding-triggered","mode":"main","binding":"alt-q"}"#

    #expect(
      try AeroSpaceEvent(json: Data(json.utf8)) == .bindingTriggered(mode: "main", binding: "alt-q")
    )
  }

  @Test func `an event missing a field it always has is malformed`() {
    #expect(
      throws: AeroSpaceError.malformed("a focused-workspace-changed event without prevWorkspace")
    ) {
      try AeroSpaceEvent(
        json: Data(#"{"_event":"focused-workspace-changed","workspace":"2"}"#.utf8))
    }
  }

  @Test func `an answer's output is its stdout when the command succeeded`() throws {
    let json = #"{"exitCode":0,"stdout":"1\n2","stderr":"","serverVersionAndHash":"0.21 abc"}"#

    #expect(try AeroSpaceWire.output(ofAnswer: Data(json.utf8)) == "1\n2")
  }

  @Test func `a failed answer carries AeroSpace's reason`() {
    let json =
      #"{"exitCode":2,"stdout":"","stderr":"Unknown command 'foo'","serverVersionAndHash":"x"}"#

    #expect(throws: AeroSpaceError.failed(exitCode: 2, stderr: "Unknown command 'foo'")) {
      try AeroSpaceWire.output(ofAnswer: Data(json.utf8))
    }
  }

  @Test func `no focused window is its own error`() {
    let json =
      #"{"exitCode":1,"stdout":"","stderr":"No window is focused","serverVersionAndHash":"x"}"#

    #expect(throws: AeroSpaceError.noWindowFocused) {
      try AeroSpaceWire.output(ofAnswer: Data(json.utf8))
    }
  }
}
