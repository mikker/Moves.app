import AXSwift
import Cocoa
import Defaults

class WindowHandler {
  var monitors: [Any?] = []
  var window: AccessibilityElement?
  private var resizeCorner: ResizeCorner?
  private var trackedWindowOrigin: CGPoint = .zero
  private var trackedWindowSize: CGSize = .zero
  private var initialMouseLocation: CGPoint = .zero

  var intention: Intention = .idle {
    didSet { intentionChanged(self.intention) }
  }

  deinit {
    removeMonitors()
  }

  func intentionChanged(_ intention: Intention) {
    removeMonitors()
    resizeCorner = nil

    if intention == .idle {
      self.window = nil
      return
    }

    let loc = Mouse.location()
    guard let window = window(at: loc) else { return }

    let app = window.application

    if let path = applicationPath(app: app),
      Defaults[.excludedApplicationPaths].contains(path)
    {
      return
    }

    guard let trackedWindowOrigin = window.position else { return }
    let trackedWindowSize: CGSize
    if intention == .resize {
      guard let size = window.size else { return }
      trackedWindowSize = size
    } else {
      trackedWindowSize = .zero
    }

    self.window = window
    self.initialMouseLocation = loc
    self.trackedWindowOrigin = trackedWindowOrigin
    self.trackedWindowSize = trackedWindowSize
    if intention == .resize && Defaults[.resizeFromClosestCorner] {
      resizeCorner = resolveResizeCorner(for: window, at: NSEvent.mouseLocation)
    }

    if Defaults[.bringToFront] {
      try? app?.setAttribute(.frontmost, value: true)
      try? window.ref.setAttribute(.main, value: true)
    }

    self.monitors.append(
      NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { event in
        self.mouseMoved(event)
      }
    )
    self.monitors.append(
      NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
        self.mouseMoved(event)
        return event
      }
    )
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

    guard let fallback = ActiveWindow.getFrontmost(), contains(loc, in: fallback) else { return nil }
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
        guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { return nil }
        guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0 else {
          return nil
        }
        guard let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha > 0 else {
          return nil
        }
        guard let bounds = CGRect.dictionary(info[kCGWindowBounds as String]) else { return nil }
        return OnScreenWindow(pid: pid, bounds: bounds)
      }
      .first { $0.bounds.contains(loc) }
  }

  private func window(matching onScreenWindow: OnScreenWindow, at loc: CGPoint) -> AccessibilityElement? {
    guard let app = Application(forProcessID: onScreenWindow.pid) else { return nil }

    let matchingWindow = windows(in: app)
      .compactMap { window -> (AccessibilityElement, CGFloat)? in
        guard let frame = frame(of: window), frame.intersects(onScreenWindow.bounds) else { return nil }
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

  private func mouseMoved(_ event: NSEvent) {
    switch intention {
    case .move: move(event)
    case .resize: resize(event)
    case .idle:
      assertionFailure("mouseMoved obseved while ignoring")
    }
  }

  private func removeMonitors() {
    monitors.forEach { (monitor) in
      guard let m = monitor else { return }
      NSEvent.removeMonitor(m)
    }
    self.monitors = []
  }

  private func move(_ event: NSEvent) {
    guard let window = self.window else { return }
    let currentMouse = Mouse.location()
    let dest = CGPoint(
      x: trackedWindowOrigin.x + (currentMouse.x - initialMouseLocation.x),
      y: trackedWindowOrigin.y + (currentMouse.y - initialMouseLocation.y)
    )
    window.moveTo(dest)
  }

  private func resize(_ event: NSEvent) {
    guard let window = self.window else { return }
    let currentMouse = Mouse.location()
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

    let corner = resizeCorner ?? resolveResizeCorner(for: window, at: NSEvent.mouseLocation)
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

    window.moveTo(CGPoint(x: newMinX, y: newMinY))
    window.resizeTo(CGSize(width: newMaxX - newMinX, height: newMaxY - newMinY))
  }

}

private struct OnScreenWindow {
  let pid: pid_t
  let bounds: CGRect
}

private extension CGRect {
  static func dictionary(_ value: Any?) -> CGRect? {
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

  let axMouseLocation: CGPoint
  if let mainScreen = NSScreen.main {
    axMouseLocation = CGPoint(
      x: mouseLocation.x,
      y: mainScreen.frame.maxY - mouseLocation.y
    )
  } else {
    axMouseLocation = mouseLocation
  }

  let minX = pos.x
  let maxX = pos.x + size.width
  let minY = pos.y
  let maxY = pos.y + size.height
  func distanceSquared(to point: CGPoint) -> CGFloat {
    let dx = axMouseLocation.x - point.x
    let dy = axMouseLocation.y - point.y
    return dx * dx + dy * dy
  }

  let candidates: [(ResizeCorner, CGFloat)] = [
    (ResizeCorner(horizontal: .min, vertical: .min), distanceSquared(to: CGPoint(x: minX, y: minY))),
    (ResizeCorner(horizontal: .max, vertical: .min), distanceSquared(to: CGPoint(x: maxX, y: minY))),
    (ResizeCorner(horizontal: .min, vertical: .max), distanceSquared(to: CGPoint(x: minX, y: maxY))),
    (ResizeCorner(horizontal: .max, vertical: .max), distanceSquared(to: CGPoint(x: maxX, y: maxY))),
  ]

  return candidates.min { $0.1 < $1.1 }?.0
}
