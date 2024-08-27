import CoreGraphics

class Mouse {
  static func location() -> CGPoint {
    if let event = CGEvent(source: nil) {
      return event.location
    } else {
      return CGPoint()
    }
  }
}
