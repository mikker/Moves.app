import AXSwift
import Cocoa

class AccessibilityElement {
  let ref: UIElement

  var window: AccessibilityElement? { findWindow() }
  var role: String? { value(.role) }
  var parent: UIElement? { value(.parent) }
  var position: CGPoint? { value(.position) }
  var size: CGSize? { value(.size) }
  var pid: pid_t? { try? ref.pid() }
  var application: Application? {
    pid == nil ? nil : Application(forProcessID: pid!)
  }

  init(ref: UIElement) {
    self.ref = ref
  }

  static func at(_ pos: CGPoint) -> AccessibilityElement? {
    do {
      guard
        let element =
          try systemWideElement.elementAtPosition(
            Float(pos.x), Float(pos.y)
          )
      else { return nil }
      return AccessibilityElement(ref: element)
    } catch { return nil }
  }

  func moveTo(_ pos: CGPoint) {
    do {
      try ref.setAttribute(.position, value: pos)
    } catch {}
  }

  func resizeTo(_ size: CGSize) {
    do {
      try ref.setAttribute(.size, value: size)
    } catch {}
  }

  // mark: Private

  private func findWindow() -> AccessibilityElement? {
    var element = self

    while element.role != kAXWindowRole {
      if let parent = element.parent {
        element = AccessibilityElement(ref: parent)
      } else {
        return nil
      }
    }

    return element
  }

  private func value<T>(_ key: Attribute) -> T? {
    do {
      return try self.ref.attribute(key)
    } catch { return nil }
  }
}
