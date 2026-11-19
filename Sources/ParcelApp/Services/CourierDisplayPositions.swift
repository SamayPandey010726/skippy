import Foundation

struct CourierDisplayPositions {
  private let defaults: UserDefaults
  private let key = "parcel.courierDisplayAnchors.v1"
  private let legacyKey = "parcel-courier-top-right"

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  func anchor(displayID: String, frame: CGRect, separate: Bool) -> CGPoint? {
    if separate {
      if let values = dictionary()[displayID], values.count == 2 {
        let point = CGPoint(x: values[0], y: values[1])
        return frame.contains(point) ? point : nil
      }
    }
    guard let values = defaults.array(forKey: legacyKey) as? [Double], values.count == 2 else { return nil }
    let point = CGPoint(x: values[0], y: values[1])
    return frame.contains(point) ? point : nil
  }

  func save(_ point: CGPoint, displayID: String, separate: Bool) {
    defaults.set([Double(point.x), Double(point.y)], forKey: legacyKey)
    guard separate else { return }
    var values = dictionary()
    values[displayID] = [Double(point.x), Double(point.y)]
    defaults.set(values, forKey: key)
  }

  func reset() {
    defaults.removeObject(forKey: key)
    defaults.removeObject(forKey: legacyKey)
  }

  private func dictionary() -> [String: [Double]] {
    defaults.dictionary(forKey: key) as? [String: [Double]] ?? [:]
  }
}
