import Cocoa
import Defaults

class Modifiers {
  typealias ChangeHandler = (Intention) -> Void

  let handleChange: ChangeHandler

  private var monitors: [Any?] = []
  private var eventTap: CFMachPort?
  private var eventTapSource: CFRunLoopSource?
  private var shortcutInProgress = false

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

    if installEventTap() { return }

    let events: NSEvent.EventTypeMask = [
      .flagsChanged, .keyDown, .mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp,
    ]
    monitors.append(contentsOf: [
      NSEvent.addGlobalMonitorForEvents(matching: events, handler: self.globalMonitor),
      NSEvent.addLocalMonitorForEvents(matching: events, handler: self.localMonitor),
    ])
  }

  func remove() {
    intention = .idle
    shortcutInProgress = false
    monitors.compactMap { $0 }.forEach(NSEvent.removeMonitor)
    monitors = []
    if let eventTapSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
      self.eventTapSource = nil
    }
    if let eventTap {
      CFMachPortInvalidate(eventTap)
      self.eventTap = nil
    }
  }

  private func intentionChanged(oldValue: Intention) {
    guard oldValue != intention else { return }
    handleChange(intention)
  }

  static func intentionFrom(_ flags: NSEvent.ModifierFlags) -> Intention {
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

  private static func modsFromFlags(_ flags: NSEvent.ModifierFlags) -> Set<Modifier> {
    var mods: Set<Modifier> = Set()
    if flags.contains(.command) { mods.insert(.command) }
    if flags.contains(.option) { mods.insert(.option) }
    if flags.contains(.control) { mods.insert(.control) }
    if flags.contains(.shift) { mods.insert(.shift) }
    if flags.contains(.function) { mods.insert(.fn) }
    return mods
  }

  private func globalMonitor(_ event: NSEvent) {
    handleEvent(type: event.type, flags: event.modifierFlags)
  }

  private func localMonitor(_ event: NSEvent) -> NSEvent? {
    globalMonitor(event)
    return event
  }

  func handleEvent(type: NSEvent.EventType, flags: NSEvent.ModifierFlags) {
    if type == .keyDown {
      shortcutInProgress = !Self.modsFromFlags(flags).isEmpty
      intention = .idle
      return
    }

    if Self.modsFromFlags(flags).isEmpty {
      shortcutInProgress = false
    }
    intention = shortcutInProgress ? .idle : Self.intentionFrom(flags)
  }

  private func installEventTap() -> Bool {
    let eventTypes: [CGEventType] = [
      .flagsChanged, .keyDown, .mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp,
    ]
    let mask = eventTypes.reduce(CGEventMask(0)) { mask, type in
      mask | (CGEventMask(1) << type.rawValue)
    }
    guard let eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .listenOnly,
      eventsOfInterest: mask,
      callback: modifiersEventTapCallback,
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    else { return false }

    self.eventTap = eventTap
    eventTapSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
    return true
  }

  fileprivate func handleEventTap(type: CGEventType, event: CGEvent) {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      shortcutInProgress = true
      intention = .idle
      if let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }
      return
    }
    handleEvent(
      type: type == .keyDown ? .keyDown : .flagsChanged,
      flags: NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
    )
  }
}

private func modifiersEventTapCallback(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  if let userInfo {
    let modifiers = Unmanaged<Modifiers>.fromOpaque(userInfo).takeUnretainedValue()
    modifiers.handleEventTap(type: type, event: event)
  }
  return Unmanaged.passUnretained(event)
}
