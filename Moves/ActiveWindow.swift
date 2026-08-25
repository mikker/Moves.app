import AXSwift
import Cocoa

class ActiveWindow {
  static func getFrontmost() -> AccessibilityElement? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    return getMainWindow(of: app)
  }

  static func getFrontmostApplication(excluding excludedPID: pid_t) -> NSRunningApplication? {
    guard
      let windowList = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else { return nil }

    for info in windowList {
      guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
        pid != excludedPID,
        let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
        layer == 0,
        let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
        alpha > 0,
        let application = NSRunningApplication(processIdentifier: pid)
      else { continue }

      return application
    }

    return nil
  }

  static func getMainWindow(of app: NSRunningApplication) -> AccessibilityElement? {
    do {
      if let appElement = Application(forProcessID: app.processIdentifier) {
        let windows: [AXUIElement]? = try appElement.attribute(.windows)
        if let windows = windows, let mainWindow = windows.first {
          return AccessibilityElement(ref: UIElement(mainWindow))
        }
      }
    } catch {
      return nil
    }

    return nil
  }

  static func applyTemplate(_ templateType: TemplateType, to window: AccessibilityElement) {
    let operation = templateType.operation

    switch operation {
    case .action(let action):
      performAction(action, on: window)

    case .position(let positionType, let size):
      let screenRect = NSScreen.main?.visibleFrame ?? .zero
      let (width, height) = size.toAbsoluteSize(for: screenRect)
      position(positionType, window: window, width: width, height: height)
    }
  }

  static func performAction(_ action: WindowAction, on window: AccessibilityElement) {
    let screenRect = NSScreen.main?.visibleFrame ?? .zero
    let windowPosition = window.position ?? .zero
    let windowSize = window.size ?? .zero

    switch action {
    case .toggleFullscreen:
      // Check if window is taking full screen and toggle
      if windowSize.width >= screenRect.width && windowSize.height >= screenRect.height {
        // Use reasonable size if currently full screen
        let size = CGSize(width: screenRect.width * 0.6, height: screenRect.height * 0.6)
        // Just use position to handle both moves and resize in correct order
        position(.center, window: window, width: size.width, height: size.height)
      } else {
        // Go full screen
        window.moveTo(CGPoint(x: screenRect.minX, y: screenRect.minY))
        window.resizeTo(CGSize(width: screenRect.width, height: screenRect.height))
      }

    case .maximizeHeight:
      // Keep current x position, maximize height
      let currentPosition = window.position ?? .zero
      let currentSize = window.size ?? .zero
      window.moveTo(CGPoint(x: currentPosition.x, y: screenRect.minY))
      window.resizeTo(CGSize(width: currentSize.width, height: screenRect.height))

    case .maximizeWidth:
      // Keep current y position, maximize width
      let currentPosition = window.position ?? .zero
      let currentSize = window.size ?? .zero
      window.moveTo(CGPoint(x: screenRect.minX, y: currentPosition.y))
      window.resizeTo(CGSize(width: screenRect.width, height: currentSize.height))

    case .previousDisplay, .nextDisplay:
      // Multi-display handling would go here
      // Currently just ensuring the window is visible on the main display
      if windowPosition.x < screenRect.minX || windowPosition.x + windowSize.width > screenRect.maxX
        || windowPosition.y < screenRect.minY
        || windowPosition.y + windowSize.height > screenRect.maxY
      {
        position(.center, window: window, width: windowSize.width, height: windowSize.height)
      }

    case .secondFourth:
      let width = screenRect.width * 0.25
      window.moveTo(CGPoint(x: screenRect.minX + width, y: screenRect.minY))
      window.resizeTo(CGSize(width: width, height: screenRect.height))

    case .thirdFourth:
      let width = screenRect.width * 0.25
      window.moveTo(CGPoint(x: screenRect.minX + width * 2, y: screenRect.minY))
      window.resizeTo(CGSize(width: width, height: screenRect.height))

    case .topCenterSixth:
      let width = screenRect.width * 0.33
      let height = screenRect.height * 0.5
      window.moveTo(CGPoint(x: screenRect.minX + width, y: screenRect.maxY - height))
      window.resizeTo(CGSize(width: width, height: height))

    case .bottomCenterSixth:
      let width = screenRect.width * 0.33
      let height = screenRect.height * 0.5
      window.moveTo(CGPoint(x: screenRect.minX + width, y: screenRect.minY))
      window.resizeTo(CGSize(width: width, height: height))
    }
  }

  static func position(
    _ position: WindowPosition, window: AccessibilityElement, width: CGFloat? = nil,
    height: CGFloat? = nil, xOffset: CGFloat = 0,
    yOffset: CGFloat = 0
  ) {
    let screenRect = NSScreen.main?.visibleFrame ?? .zero
    let currentPosition = window.position ?? .zero

    // Get target size - either specified or current
    let windowSize: CGSize
    if let width = width, let height = height {
      windowSize = CGSize(width: width, height: height)
    } else {
      windowSize = window.size ?? .zero
    }

    // Calculate the position based on target size
    var newPosition: CGPoint = .zero

    switch position {
    case .centerRight:
      newPosition = CGPoint(
        x: screenRect.maxX - windowSize.width + xOffset,
        y: screenRect.midY - windowSize.height / 2 + yOffset
      )
    case .center:
      newPosition = CGPoint(
        x: screenRect.midX - windowSize.width / 2 + xOffset,
        y: screenRect.midY - windowSize.height / 2 + yOffset
      )
    case .centerLeft:
      newPosition = CGPoint(
        x: screenRect.minX + xOffset,
        y: screenRect.midY - windowSize.height / 2 + yOffset
      )
    case .topRight:
      newPosition = CGPoint(
        x: screenRect.maxX - windowSize.width + xOffset,
        y: screenRect.maxY - windowSize.height + yOffset
      )
    case .topLeft:
      newPosition = CGPoint(
        x: screenRect.minX + xOffset,
        y: screenRect.maxY - windowSize.height + yOffset
      )
    case .bottomRight:
      newPosition = CGPoint(
        x: screenRect.maxX - windowSize.width + xOffset,
        y: screenRect.minY + yOffset
      )
    case .bottomLeft:
      newPosition = CGPoint(
        x: screenRect.minX + xOffset,
        y: screenRect.minY + yOffset
      )
    case .relative:
      // Keep the current position
      newPosition = currentPosition
    }

    // First move to the correct position
    window.moveTo(newPosition)

    // Then resize if needed - this way we ensure the window is positioned correctly
    // regardless of its size
    if let width = width, let height = height {
      let size = CGSize(width: width, height: height)
      window.resizeTo(size)
    }
  }

}
