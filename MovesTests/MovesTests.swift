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
}
