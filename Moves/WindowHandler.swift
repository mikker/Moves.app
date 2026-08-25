import AXSwift
import Cocoa
import Defaults

class WindowHandler {
  var monitors: [Any?] = []
  var window: AccessibilityElement?
  private var eventTap: CFMachPort?
  private var eventTapSource: CFRunLoopSource?
  private var resizeCorner: ResizeCorner?
  private var trackedWindowOrigin: CGPoint = .zero
  private var trackedWindowSize: CGSize = .zero
  private var initialMouseLocation: CGPoint = .zero
  private var pendingMouseLocation: CGPoint?
  private var mouseMoveScheduled = false

  var intention: Intention = .idle {
    didSet { intentionChanged(self.intention) }
  }

  deinit {
    removeMonitors()
  }

  func intentionChanged(_ intention: Intention) {
    removeMonitors()
    self.window = nil
    resizeCorner = nil
    pendingMouseLocation = nil

    if intention == .idle {
      return
    }

    if Defaults[.requireClick] {
      observeMouseDown()
    } else {
      beginHandling()
    }
  }

  private func observeMouseDown() {
    if installEventTap() {
      return
    }

    monitors.append(
      NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
        self.beginHandling()
      }
    )
    monitors.append(
      NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
        self.beginHandling()
        return event
      }
    )
  }

  @discardableResult
  private func beginHandling(at loc: CGPoint = Mouse.location()) -> Bool {
    guard let window = window(at: loc) else { return false }

    let app = window.application

    if let path = applicationPath(app: app),
      Defaults[.excludedApplicationPaths].contains(path)
    {
      return false
    }

    guard let trackedWindowOrigin = window.position else { return false }
    let trackedWindowSize: CGSize
    if intention == .resize {
      guard let size = window.size else { return false }
      trackedWindowSize = size
    } else {
      trackedWindowSize = .zero
    }

    self.window = window
    self.initialMouseLocation = loc
    self.trackedWindowOrigin = trackedWindowOrigin
    self.trackedWindowSize = trackedWindowSize
    if intention == .resize && Defaults[.resizeFromClosestCorner] {
      resizeCorner = resolveResizeCorner(for: window, at: loc)
    }

    if Defaults[.bringToFront] {
      try? app?.setAttribute(.frontmost, value: true)
      try? window.ref.setAttribute(.main, value: true)
    }

    if eventTap != nil {
      return true
    }

    removeMonitors()

    let movementEvents: NSEvent.EventTypeMask =
      Defaults[.requireClick]
      ? [.mouseMoved, .leftMouseDragged]
      : .mouseMoved
    monitors.append(
      NSEvent.addGlobalMonitorForEvents(matching: movementEvents) { _ in
        self.mouseMoved(at: Mouse.location())
      }
    )
    monitors.append(
      NSEvent.addLocalMonitorForEvents(matching: movementEvents) { event in
        self.mouseMoved(at: Mouse.location())
        return event
      }
    )

    if Defaults[.requireClick] {
      observeMouseUp()
    }
    return true
  }

  private func observeMouseUp() {
    monitors.append(
      NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
        self.finishHandling()
      }
    )
    monitors.append(
      NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
        self.finishHandling()
        return event
      }
    )
  }

  private func finishHandling() {
    window = nil
    resizeCorner = nil

    if eventTap != nil {
      return
    }

    removeMonitors()
    if intention != .idle {
      observeMouseDown()
    }
  }

  private func window(at loc: CGPoint) -> AccessibilityElement? {
    let element = AccessibilityElement.at(loc)

    if let window = element?.window {
      return window
    }

    if let onScreenWindow = onScreenWindow(at: loc),
      let window = window(matching: onScreenWindow, at: loc)
    {
      return window
    }

    if let app = element?.application,
      let window = window(containing: loc, in: app)
    {
      return window
    }

    guard let fallback = ActiveWindow.getFrontmost(), contains(loc, in: fallback) else {
      return nil
    }
    return fallback
  }

  private func onScreenWindow(at loc: CGPoint) -> OnScreenWindow? {
    guard
      let windowList =
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]]
    else { return nil }

    return windowList.lazy
      .compactMap { info in
        guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else {
          return nil
        }
        guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0 else {
          return nil
        }
        guard let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha > 0
        else {
          return nil
        }
        guard let bounds = CGRect.dictionary(info[kCGWindowBounds as String]) else { return nil }
        return OnScreenWindow(pid: pid, bounds: bounds)
      }
      .first { $0.bounds.contains(loc) }
  }

  private func window(matching onScreenWindow: OnScreenWindow, at loc: CGPoint)
    -> AccessibilityElement?
  {
    guard let app = Application(forProcessID: onScreenWindow.pid) else { return nil }

    let matchingWindow = windows(in: app)
      .compactMap { window -> (AccessibilityElement, CGFloat)? in
        guard let frame = frame(of: window), frame.intersects(onScreenWindow.bounds) else {
          return nil
        }
        return (window, frameDistance(frame, onScreenWindow.bounds))
      }
      .min { $0.1 < $1.1 }?
      .0

    if let matchingWindow {
      return matchingWindow
    }

    return window(containing: loc, in: app)
  }

  private func window(containing loc: CGPoint, in app: Application) -> AccessibilityElement? {
    windows(in: app).first { contains(loc, in: $0) }
  }

  private func windows(in app: Application) -> [AccessibilityElement] {
    guard let windows: [AXUIElement] = try? app.attribute(.windows) else { return [] }
    return windows.map { AccessibilityElement(ref: UIElement($0)) }
  }

  private func frame(of window: AccessibilityElement) -> CGRect? {
    guard let origin = window.position, let size = window.size else { return nil }
    return CGRect(origin: origin, size: size)
  }

  private func contains(_ loc: CGPoint, in window: AccessibilityElement) -> Bool {
    guard let frame = frame(of: window) else { return false }
    return frame.contains(loc)
  }

  private func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    abs(lhs.minX - rhs.minX) + abs(lhs.minY - rhs.minY) + abs(lhs.width - rhs.width)
      + abs(lhs.height - rhs.height)
  }

  private func getBundleID(for axApplication: AXUIElement) -> String? {
    var pid: pid_t = 0
    if AXUIElementGetPid(axApplication, &pid) == .success {
      if let app = NSRunningApplication(processIdentifier: pid) {
        return app.bundleIdentifier
      }
    }
    return nil
  }

  private func applicationPath(app maybeApp: Application?) -> String? {
    guard let app = maybeApp else {
      print("no app")
      return nil
    }
    guard let bundleId: String = getBundleID(for: app.element) else {
      print("no bundle id")
      return nil
    }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
      print("no url")
      return nil
    }
    let path = url.path
    return path.hasSuffix("/") ? path : path.appending("/")
  }

  private func mouseMoved(at location: CGPoint) {
    switch intention {
    case .move: move(to: location)
    case .resize: resize(to: location)
    case .idle:
      assertionFailure("mouseMoved obseved while ignoring")
    }
  }

  private func scheduleMouseMoved(to location: CGPoint) {
    pendingMouseLocation = location
    guard !mouseMoveScheduled else { return }
    mouseMoveScheduled = true

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.mouseMoveScheduled = false
      guard let location = self.pendingMouseLocation else { return }
      self.pendingMouseLocation = nil
      self.mouseMoved(at: location)
    }
  }

  private func removeMonitors() {
    monitors.forEach { (monitor) in
      guard let m = monitor else { return }
      NSEvent.removeMonitor(m)
    }
    self.monitors = []

    if let eventTapSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
      self.eventTapSource = nil
    }
    if let eventTap {
      CFMachPortInvalidate(eventTap)
      self.eventTap = nil
    }
  }

  private func installEventTap() -> Bool {
    let eventTypes: [CGEventType] = [
      .leftMouseDown, .mouseMoved, .leftMouseDragged, .leftMouseUp,
    ]
    let mask = eventTypes.reduce(CGEventMask(0)) { mask, type in
      mask | (CGEventMask(1) << type.rawValue)
    }
    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: windowHandlerEventTapCallback,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      ),
      let eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    else { return false }

    self.eventTap = eventTap
    self.eventTapSource = eventTapSource
    CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
    return true
  }

  fileprivate func handleEventTap(type: CGEventType, event: CGEvent) -> Bool {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }
      return false
    }

    switch type {
    case .leftMouseDown:
      return beginHandling(at: event.location)
    case .mouseMoved, .leftMouseDragged:
      guard window != nil else { return false }
      scheduleMouseMoved(to: event.location)
      return type == .leftMouseDragged
    case .leftMouseUp:
      guard window != nil else { return false }
      scheduleMouseMoved(to: event.location)
      DispatchQueue.main.async { [weak self] in
        self?.finishHandling()
      }
      return true
    default:
      return false
    }
  }

  private func move(to currentMouse: CGPoint) {
    guard let window = self.window else { return }
    let dest = CGPoint(
      x: trackedWindowOrigin.x + (currentMouse.x - initialMouseLocation.x),
      y: trackedWindowOrigin.y + (currentMouse.y - initialMouseLocation.y)
    )
    window.moveTo(dest)
  }

  private func resize(to currentMouse: CGPoint) {
    guard let window = self.window else { return }
    let dx = currentMouse.x - initialMouseLocation.x
    let dy = currentMouse.y - initialMouseLocation.y

    if !Defaults[.resizeFromClosestCorner] {
      let dest = CGSize(
        width: max(50, trackedWindowSize.width + dx),
        height: max(50, trackedWindowSize.height + dy)
      )
      window.resizeTo(dest)
      return
    }

    let corner = resizeCorner ?? resolveResizeCorner(for: window, at: currentMouse)
    resizeCorner = corner
    guard let corner else { return }

    let initMinX = trackedWindowOrigin.x
    let initMaxX = trackedWindowOrigin.x + trackedWindowSize.width
    let initMinY = trackedWindowOrigin.y
    let initMaxY = trackedWindowOrigin.y + trackedWindowSize.height

    let movingX = (corner.horizontal == .min ? initMinX : initMaxX) + dx
    let movingY = (corner.vertical == .min ? initMinY : initMaxY) + dy
    let fixedX = corner.horizontal == .min ? initMaxX : initMinX
    let fixedY = corner.vertical == .min ? initMaxY : initMinY

    let newMinX = min(movingX, fixedX)
    let newMaxX = max(movingX, fixedX)
    let newMinY = min(movingY, fixedY)
    let newMaxY = max(movingY, fixedY)

    window.setFrame(
      CGRect(
        x: newMinX,
        y: newMinY,
        width: newMaxX - newMinX,
        height: newMaxY - newMinY
      )
    )
  }

}

private func windowHandlerEventTapCallback(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  let handler = Unmanaged<WindowHandler>.fromOpaque(userInfo).takeUnretainedValue()
  return handler.handleEventTap(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}

private struct OnScreenWindow {
  let pid: pid_t
  let bounds: CGRect
}

extension CGRect {
  fileprivate static func dictionary(_ value: Any?) -> CGRect? {
    guard let dictionary = value as? NSDictionary else { return nil }
    return CGRect(dictionaryRepresentation: dictionary)
  }
}

private enum ResizeAxisEdge {
  case min
  case max
}

private struct ResizeCorner {
  let horizontal: ResizeAxisEdge
  let vertical: ResizeAxisEdge
}

private func resolveResizeCorner(
  for window: AccessibilityElement,
  at mouseLocation: CGPoint
) -> ResizeCorner? {
  guard let size = window.size else { return nil }
  guard let pos = window.position else { return nil }

  let minX = pos.x
  let maxX = pos.x + size.width
  let minY = pos.y
  let maxY = pos.y + size.height
  func distanceSquared(to point: CGPoint) -> CGFloat {
    let dx = mouseLocation.x - point.x
    let dy = mouseLocation.y - point.y
    return dx * dx + dy * dy
  }

  let candidates: [(ResizeCorner, CGFloat)] = [
    (
      ResizeCorner(horizontal: .min, vertical: .min), distanceSquared(to: CGPoint(x: minX, y: minY))
    ),
    (
      ResizeCorner(horizontal: .max, vertical: .min), distanceSquared(to: CGPoint(x: maxX, y: minY))
    ),
    (
      ResizeCorner(horizontal: .min, vertical: .max), distanceSquared(to: CGPoint(x: minX, y: maxY))
    ),
    (
      ResizeCorner(horizontal: .max, vertical: .max), distanceSquared(to: CGPoint(x: maxX, y: maxY))
    ),
  ]

  return candidates.min { $0.1 < $1.1 }?.0
}
