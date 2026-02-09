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
    guard let window = AccessibilityElement.at(loc)?.window else { return }

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
