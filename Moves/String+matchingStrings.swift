import Foundation

extension String {
  func matchingStrings(regex: String) -> [[String?]] {
    guard let regex = try? NSRegularExpression(pattern: regex, options: []) else { return [] }
    let nsString = self as NSString
    let results = regex.matches(in: self, options: [], range: NSMakeRange(0, nsString.length))
    return results.map { result in
      (0..<result.numberOfRanges).map {
        result.range(at: $0).location != NSNotFound
          ? nsString.substring(with: result.range(at: $0))
          : nil
      }
    }
  }
}
