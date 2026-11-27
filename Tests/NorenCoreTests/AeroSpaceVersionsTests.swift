import NorenCore
import Testing

@Suite struct AeroSpaceVersionsTests {
  @Test func `the same build running is not another build`() throws {
    let versions = try #require(
      AeroSpaceVersions(
        output: """
          aerospace CLI client version: 0.21.3-Beta d69a64d833ca2cfe0e088cfae8e5e9751ec9eff3
          AeroSpace.app server version: 0.21.3-Beta d69a64d833ca2cfe0e088cfae8e5e9751ec9eff3
          """))

    #expect(versions.appIsOtherBuild == false)
  }

  @Test func `an app at another commit is another build`() throws {
    let versions = try #require(
      AeroSpaceVersions(
        output: """
          aerospace CLI client version: 0.21.3-Beta d69a64d833ca2cfe0e088cfae8e5e9751ec9eff3
          AeroSpace.app server version: 0.21.3-Beta 167a0cf0000000000000000000000000000000000
          """))

    #expect(versions.app == "0.21.3-Beta 167a0cf0000000000000000000000000000000000")
    #expect(versions.appIsOtherBuild)
  }

  @Test func `with no app answering there is nothing to restart`() throws {
    let versions = try #require(
      AeroSpaceVersions(
        output: "aerospace CLI client version: 0.21.3-Beta d69a64d833ca2cfe0e088cfae8e5e9751ec9eff3"
      ))

    #expect(versions.app == nil)
    #expect(versions.appIsOtherBuild == false)
  }

  @Test func `output without the command's version is none`() {
    #expect(AeroSpaceVersions(output: "Can't connect to AeroSpace server") == nil)
  }
}
