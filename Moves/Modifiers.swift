import Cocoa
import Defaults

class Modifiers {
  typealias ChangeHandler = (Intention) -> Void

  let handleChange: ChangeHandler

  var onMonitors: [Any?] = []
  var offMonitors: [Any?] = []

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

    onMonitors.append(contentsOf: [
      NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: self.globalMonitor),
      NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: self.localMonitor),
    ])
  }

  func remove() {
    removeOffMonitors()
    removeOnMonitors()
  }

  private func removeOnMonitors() {
    offMonitors.forEach { (monitor) in
      guard let m = monitor else { return }
      NSEvent.removeMonitor(m)
    }

    offMonitors = []
  }

  private func removeOffMonitors() {
    offMonitors.forEach { (monitor) in
      guard let m = monitor else { return }
      NSEvent.removeMonitor(m)
    }

    offMonitors = []
  }

  private func intentionChanged(oldValue: Intention) {
    guard oldValue != intention else { return }

    //    print("intention:\(intention)")

    if intention == .idle {
      removeOffMonitors()
    } else {
      setupOffMonitors()
    }

    handleChange(intention)
  }

  private func intentionFrom(_ flags: NSEvent.ModifierFlags) -> Intention {
    let mods = modsFromFlags(flags)

    if mods.isEmpty { return .idle }

    let moveMods = Defaults[.moveModifiers]
    let resizeMods = Defaults[.resizeModifiers]

    if !moveMods.isEmpty && mods == moveMods {
      return .move
    } else if !resizeMods.isEmpty && mods == resizeMods {
      return .resize
    } else {
      return .idle
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

  private func setupOffMonitors() {
    offMonitors.append(contentsOf: [
      NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: self.globalMonitor),
      NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: self.localMonitor),
    ])
  }

  private func globalMonitor(_ event: NSEvent) {
    self.intention = self.intentionFrom(event.modifierFlags)
  }

  private func localMonitor(_ event: NSEvent) -> NSEvent? {
    globalMonitor(event)
    return event
  }
}
