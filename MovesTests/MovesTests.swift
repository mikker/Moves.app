import XCTest

@testable import Moves

class MovesTests: XCTestCase {

  override func setUp() {
    // Put setup code here. This method is called before the invocation of each test method in the class.
  }

  override func tearDown() {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
  }

  func testRegex() {
    let input = "file:///Applications/Xcode.app/"
    let pattern = "^file://(.*)/$"
    let matches = input.matchingStrings(regex: pattern)
    let result = matches[0][1]

    assert(result == "/Applications/Xcode.app")
  }

  func testExclusionMatchesPathsStoredWithoutTrailingSlash() {
    let excluded: Set<String> = ["/Applications/Adobe InDesign 2025/Adobe InDesign 2025.app"]

    XCTAssertTrue(
      AppExclusion.isExcluded(
        "/Applications/Adobe InDesign 2025/Adobe InDesign 2025.app", in: excluded))
    XCTAssertTrue(
      AppExclusion.isExcluded(
        "/Applications/Adobe InDesign 2025/Adobe InDesign 2025.app/", in: excluded))
  }

  func testExclusionMatchesLegacyPathsStoredWithTrailingSlash() {
    let excluded: Set<String> = ["/Applications/Xcode.app/"]

    XCTAssertTrue(AppExclusion.isExcluded("/Applications/Xcode.app", in: excluded))
    XCTAssertTrue(AppExclusion.isExcluded("/Applications/Xcode.app/", in: excluded))
  }

  func testExclusionDoesNotMatchOtherApps() {
    let excluded: Set<String> = ["/Applications/Xcode.app/"]

    XCTAssertFalse(AppExclusion.isExcluded("/Applications/Safari.app", in: excluded))
  }
}
