// Captures the display on its own clock while the other process moves the real pointer.
import AVFoundation
import Foundation
import ScreenCaptureKit

final class RecordingDelegate: NSObject, SCRecordingOutputDelegate {
  let directory: URL
  init(_ directory: URL) { self.directory = directory }
  func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
    FileManager.default.createFile(atPath: directory.appendingPathComponent("capture.ready").path, contents: Data(String(Date().timeIntervalSince1970).utf8))
  }
  func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
    fputs("ScreenCaptureKit: \(error)\n", stderr)
    exit(1)
  }
  func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
    FileManager.default.createFile(atPath: directory.appendingPathComponent("capture.finished").path, contents: Data(String(Date().timeIntervalSince1970).utf8))
  }
}

@main struct DisplayRecorder {
  static func main() async throws {
    let args = CommandLine.arguments
    let dir = URL(fileURLWithPath: args[1], isDirectory: true)
    let crop = CGRect(x: Double(args[2])!, y: Double(args[3])!, width: Double(args[4])!, height: Double(args[5])!)
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else { exit(1) }
    let config = SCStreamConfiguration()
    config.sourceRect = crop
    config.width = Int(crop.width) / 2 * 2; config.height = Int(crop.height) / 2 * 2
    if args.last == "HD" { config.width = 1920; config.height = 1080 }
    print("Recording display", display.width, "×", display.height, "points, crop", crop, "output", config.width, "×", config.height)
    config.showsCursor = true; config.capturesAudio = false
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: nil)
    let movie = SCRecordingOutputConfiguration()
    movie.outputURL = dir.appendingPathComponent("WindowServer.mp4")
    movie.outputFileType = .mp4
    movie.videoCodecType = .h264
    let delegate = RecordingDelegate(dir)
    let output = SCRecordingOutput(configuration: movie, delegate: delegate)
    try stream.addRecordingOutput(output)
    try await stream.startCapture()
    // EOF also ends the capture if the pointer-driving process exits abnormally.
    _ = await Task.detached { readLine() }.value
    try await stream.stopCapture()
    for _ in 0..<100 {
      if FileManager.default.fileExists(atPath: dir.appendingPathComponent("capture.finished").path) { return }
      try await Task.sleep(for: .milliseconds(50))
    }
    throw CocoaError(.fileWriteUnknown)
  }
}
