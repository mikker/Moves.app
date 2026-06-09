import Cocoa
import Defaults

enum Modifier: String, Defaults.Serializable {
  case command = "command"
  case option = "option"
  case control = "control"
  case shift = "shift"
  case fn = "fn"
}

enum MouseButton: String, Defaults.Serializable {
  case left = "left"
  case right = "right"
}

extension Defaults.Keys {
  static let accessibilityEnabled = Key<Bool>("accessibilityEnabled", default: false)

  static let moveModifiers = Key<Set<Modifier>>(
    "moveModifiers", default: Set(arrayLiteral: .command, .shift))

  static let resizeModifiers = Key<Set<Modifier>>(
    "resizeModifiers", default: Set(arrayLiteral: .option, .shift))

  static let moveMouseButtons = Key<Set<MouseButton>>("moveMouseButtons", default: [])
  static let resizeMouseButtons = Key<Set<MouseButton>>("resizeMouseButtons", default: [])

  static let bringToFront = Key<Bool>("bringToFront", default: false)

  static let resizeFromClosestCorner = Key<Bool>("resizeFromClosestCorner", default: true)

  static let showSettingsOnLaunch = Key<Bool>("showSettingsOnLaunch", default: true)
  static let showInMenubar = Key<Bool>("showInMenubar", default: true)

  static let excludedApplicationPaths = Key<Set<String>>("excludedApplicationPaths", default: [])
}
