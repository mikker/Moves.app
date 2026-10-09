import XCTest
import Cocoa
import Defaults

@testable import Moves

class MovesTests: XCTestCase {

  private var moveModifiers: Set<Modifier> = []
  private var resizeModifiers: Set<Modifier> = []
  private var requireClick = false

  override func setUp() {
    super.setUp()
    moveModifiers = Defaults[.moveModifiers]
    resizeModifiers = Defaults[.resizeModifiers]
    requireClick = Defaults[.requireClick]
    Defaults[.moveModifiers] = [.command, .shift]
    Defaults[.resizeModifiers] = [.option, .shift]
    Defaults[.requireClick] = true
  }

  override func tearDown() {
    Defaults[.moveModifiers] = moveModifiers
    Defaults[.resizeModifiers] = resizeModifiers
    Defaults[.requireClick] = requireClick
    super.tearDown()
  }

  func testScreenshotShortcutCancelsMoveUntilModifiersAreReleased() {
    var changes: [Intention] = []
    let modifiers = Modifiers { changes.append($0) }
    modifiers.handleEvent(type: .flagsChanged, flags: [.command, .shift])
    XCTAssertEqual(modifiers.intention, .move)

    modifiers.handleEvent(type: .keyDown, flags: [.command, .shift])
    for type: NSEvent.EventType in [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp] {
      modifiers.handleEvent(type: type, flags: [.command, .shift])
      XCTAssertEqual(modifiers.intention, .idle)
    }
    modifiers.handleEvent(type: .flagsChanged, flags: [.shift])
    XCTAssertEqual(modifiers.intention, .idle)
    modifiers.handleEvent(type: .flagsChanged, flags: [])
    modifiers.handleEvent(type: .flagsChanged, flags: [.command, .shift])
    XCTAssertEqual(changes, [.move, .idle, .move])
  }

  func testScreenshotShortcutCancelsClickDrivenResize() {
    Defaults[.moveModifiers] = [.command]
    Defaults[.resizeModifiers] = [.command, .shift]
    let handler = WindowHandler()
    let modifiers = Modifiers { handler.intention = $0 }
    modifiers.handleEvent(type: .flagsChanged, flags: [.command])
    modifiers.handleEvent(type: .flagsChanged, flags: [.command, .shift])
    XCTAssertEqual(handler.intention, .resize)

    modifiers.handleEvent(type: .keyDown, flags: [.command, .shift])
    modifiers.handleEvent(type: .flagsChanged, flags: [.command])
    modifiers.handleEvent(type: .leftMouseDragged, flags: [.command])
    XCTAssertEqual(handler.intention, .idle)
    XCTAssertTrue(handler.monitors.isEmpty)
    XCTAssertNil(handler.window)
  }

  func testMouseEventRecoversFromMissingModifierRelease() {
    let modifiers = Modifiers { _ in }
    modifiers.handleEvent(type: .flagsChanged, flags: [.command, .shift])
    modifiers.handleEvent(type: .leftMouseDragged, flags: [])
    XCTAssertEqual(modifiers.intention, .idle)
  }

  func testMouseEventClearsShortcutSuppressionAfterMissingModifierRelease() {
    for type: NSEvent.EventType in [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp] {
      var changes: [Intention] = []
      let modifiers = Modifiers { changes.append($0) }
      modifiers.handleEvent(type: .flagsChanged, flags: [.command, .shift])
      modifiers.handleEvent(type: .keyDown, flags: [.command, .shift])
      modifiers.handleEvent(type: type, flags: [])
      modifiers.handleEvent(type: .flagsChanged, flags: [.command, .shift])
      XCTAssertEqual(changes, [.move, .idle, .move])
    }
  }

  func testWindowHandlerRejectsStaleModifiers() {
    let handler = WindowHandler()
    handler.intention = .move
    XCTAssertTrue(handler.validateModifiers(flags: [.command, .shift]))
    XCTAssertFalse(handler.validateModifiers(flags: []))
    XCTAssertEqual(handler.intention, .idle)
    XCTAssertTrue(handler.monitors.isEmpty)
  }

  func testRemovingModifiersStopsHandling() {
    var changes: [Intention] = []
    let modifiers = Modifiers { changes.append($0) }
    modifiers.handleEvent(type: .flagsChanged, flags: [.option, .shift])
    modifiers.remove()
    XCTAssertEqual(changes, [.resize, .idle])
  }

  func testRegex() {
    let input = "file:///Applications/Xcode.app/"
    let pattern = "^file://(.*)/$"
    let matches = input.matchingStrings(regex: pattern)
    let result = matches[0][1]

    assert(result == "/Applications/Xcode.app")
  }
}
