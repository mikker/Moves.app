import AXSwift
import Cocoa
import Defaults

class WindowHandler {
  var monitors: [Any?] = []
  var window: AccessibilityElement?

  var intention: Intention = .idle {
    didSet { intentionChanged(self.intention) }
  }

  deinit {
    removeMonitors()
  }

  func intentionChanged(_ intention: Intention) {
    removeMonitors()

    if intention == .idle {
      self.window = nil
      return
    }

    let loc = Mouse.location()
    guard let window = AccessibilityElement.at(loc)?.window else { return }

    let app = window.application

    // App is excluded?

    if let path = applicationPath(app: app),
      Defaults[.excludedApplicationPaths].contains(path)
    {
      return
    }

    self.window = window

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
    guard let pos = window.position else { return }
    let dest = CGPoint(x: pos.x + event.deltaX, y: pos.y + event.deltaY)
    window.moveTo(dest)
  }

  private func resize(_ event: NSEvent) {
    guard let window = self.window else { return }
    guard let size = window.size else { return }
    let dest = CGSize(width: size.width + event.deltaX, height: size.height + event.deltaY)
    window.resizeTo(dest)
  }

}
