import NorenCore
import Testing

@Suite struct DisplayModeTests {
  let modes = [
    DisplayMode(width: 1800, height: 1169, pixelWidth: 1800, pixelHeight: 1169, refreshRate: 120),
    DisplayMode(width: 1800, height: 1169, pixelWidth: 3600, pixelHeight: 2338, refreshRate: 60),
    DisplayMode(width: 1800, height: 1169, pixelWidth: 3600, pixelHeight: 2338, refreshRate: 120),
    DisplayMode(width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 120),
  ]

  @Test func `each size is listed once, smallest first, by its sharpest fastest mode`() {
    #expect(
      DisplayMode.bestForEachSize(of: modes) == [
        DisplayMode(
          width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 120),
        DisplayMode(
          width: 1800, height: 1169, pixelWidth: 3600, pixelHeight: 2338, refreshRate: 120),
      ])
  }

  @Test func `a size is picked by its sharpest mode before a faster blurry one`() {
    #expect(
      DisplayMode.best(width: 1800, height: 1169, of: Array(modes.prefix(2)))
        == DisplayMode(
          width: 1800, height: 1169, pixelWidth: 3600, pixelHeight: 2338, refreshRate: 60))
  }

  @Test func `a size the display does not offer has no mode`() {
    #expect(DisplayMode.best(width: 1024, height: 768, of: modes) == nil)
  }
}
