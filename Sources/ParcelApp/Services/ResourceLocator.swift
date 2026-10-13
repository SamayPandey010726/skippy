import AppKit
import Foundation

enum ResourceLocator {
  static func url(_ name: String, extension ext: String) -> URL? {
    if let direct = Bundle.main.url(forResource: name, withExtension: ext) { return direct }
    if let bundleURL = Bundle.main.url(forResource: "Parcel_ParcelApp", withExtension: "bundle"),
      let bundle = Bundle(url: bundleURL),
      let url = bundle.url(forResource: name, withExtension: ext)
    {
      return url
    }
    return Bundle.module.url(forResource: name, withExtension: ext)
  }
}
@MainActor final class FeedbackSounds {
  static let shared = FeedbackSounds()
  private var current: NSSound?
  func seal() {
    guard let url = ResourceLocator.url("paper-seal", extension: "wav"),
      let sound = NSSound(contentsOf: url, byReference: true)
    else { return }
    current?.stop()
    current = sound
    sound.volume = 0.35
    sound.play()
  }
}
