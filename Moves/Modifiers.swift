import Cocoa
import Defaults

class Modifiers {
  typealias ChangeHandler = (Intention) -> Void

  let handleChange: ChangeHandler

  var monitors: [Any?] = []
  private var activeModifiers: Set<Modifier> = []
  private var isLeftMouseDown = false
  private var isRightMouseDown = false

  var intention: Intention = .idle {
    didSet { intentionChanged(oldValue: oldValue) }
  }

  init(changeHandler: @escaping ChangeHandler) {
    self.handleChange = changeHandler
  }

  deinit {
    remove()
  }

  func observe() {
    remove()
    activeModifiers = []
    isLeftMouseDown = false
    isRightMouseDown = false
    monitors.append(contentsOf: [
      NSEvent.addGlobalMonitorForEvents(
        matching: [.flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp],
        handler: self.globalMonitor
      ),
      NSEvent.addLocalMonitorForEvents(
        matching: [.flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
      ) { event in
        self.localMonitor(event)
      },
    ])
  }

  func remove() {
    monitors.forEach { monitor in
      guard let monitor else { return }
      NSEvent.removeMonitor(monitor)
    }
    monitors = []
    activeModifiers = []
    isLeftMouseDown = false
    isRightMouseDown = false
    intention = .idle
  }

  private func intentionChanged(oldValue: Intention) {
    guard oldValue != intention else { return }
    handleChange(intention)
  }

  private func intentionFromCurrentState() -> Intention {
    let moveMods = Defaults[.moveModifiers]
    let resizeMods = Defaults[.resizeModifiers]
    let moveButtons = Defaults[.moveMouseButtons]
    let resizeButtons = Defaults[.resizeMouseButtons]

    if !moveMods.isEmpty && activeModifiers == moveMods && areButtonsPressed(moveButtons) {
      return .move
    } else if !resizeMods.isEmpty && activeModifiers == resizeMods && areButtonsPressed(resizeButtons) {
      return .resize
    } else {
      return .idle
    }
  }

  private func areButtonsPressed(_ buttons: Set<MouseButton>) -> Bool {
    if buttons.isEmpty {
      return false
    }

    return buttons.allSatisfy { button in
      switch button {
      case .left:
        return isLeftMouseDown
      case .right:
        return isRightMouseDown
      }
    }
  }

  private func modsFromFlags(_ flags: NSEvent.ModifierFlags) -> Set<Modifier> {
    var mods: Set<Modifier> = Set()
    if flags.contains(.command) { mods.insert(.command) }
    if flags.contains(.option) { mods.insert(.option) }
    if flags.contains(.control) { mods.insert(.control) }
    if flags.contains(.shift) { mods.insert(.shift) }
    if flags.contains(.function) { mods.insert(.fn) }
    return mods
  }

  private func globalMonitor(_ event: NSEvent) {
    activeModifiers = modsFromFlags(event.modifierFlags)
    switch event.type {
    case .leftMouseDown:
      isLeftMouseDown = true
    case .leftMouseUp:
      isLeftMouseDown = false
    case .rightMouseDown:
      isRightMouseDown = true
    case .rightMouseUp:
      isRightMouseDown = false
    default:
      break
    }
    intention = intentionFromCurrentState()
  }

  private func localMonitor(_ event: NSEvent) -> NSEvent? {
    globalMonitor(event)
    return event
  }
}
