import AVFoundation
import Foundation
import ParcelCore

enum VideoQuality: String, CaseIterable, Identifiable, Codable {
  case small, balanced, high
  var id: String { rawValue }
  var preset: String {
    switch self {
    case .small: return AVAssetExportPresetLowQuality
    case .balanced: return AVAssetExportPresetMediumQuality
    case .high: return AVAssetExportPresetHighestQuality
    }
  }
}

struct VideoRecipe: Equatable {
  var maximumDimension: Int
  var quality: VideoQuality
  init(maximumDimension: Int = 1280, quality: VideoQuality = .balanced) {
    self.maximumDimension = maximumDimension
    self.quality = quality
  }
}

struct PreparedVideo: Sendable {
  var url: URL
  var bytes: Int64
  var description: String
}

enum VideoPipeline {
  static func canPrepare(_ url: URL) -> Bool {
    ["mov", "mp4", "m4v", "avi", "mkv"].contains(url.pathExtension.lowercased())
  }
  static func outputSize(source: CGSize, maximum: Int) -> CGSize {
    let longest = max(source.width, source.height)
    guard longest > 0, maximum > 0 else { return .zero }
    let ratio = min(1, CGFloat(maximum) / longest)
    return CGSize(width: max(2, floor(source.width * ratio / 2) * 2),
                  height: max(2, floor(source.height * ratio / 2) * 2))
  }
  static func prepare(source: URL, recipe: VideoRecipe, token: CancellationToken,
                      directory: URL = StoragePaths.prepared) async throws -> PreparedVideo {
    try token.check()
    guard [480, 720, 1280, 1920, 3840].contains(recipe.maximumDimension) else {
      throw ParcelError.storageError("Choose a supported video size.")
    }
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("Parcel-video-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let snapshot = scratch.appendingPathComponent(source.lastPathComponent)
    try await Task.detached(priority: .utility) {
      _ = try CoordinatedFiles.read(source) { actual in
        try FileTree.copy(actual, to: snapshot, cleanMetadata: false, token: token)
      }
    }.value
    try token.check()
    let asset = AVURLAsset(url: snapshot)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    guard let track = tracks.first, tracks.count == 1, try await !asset.load(.hasProtectedContent) else {
      throw ParcelError.storageError("This video cannot be prepared safely. Send its original instead.")
    }
    let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
    let bounds = CGRect(origin: .zero, size: naturalSize).applying(transform)
    let size = outputSize(source: CGSize(width: abs(bounds.width), height: abs(bounds.height)), maximum: recipe.maximumDimension)
    guard size.width > 0, size.height > 0,
      let session = AVAssetExportSession(asset: asset, presetName: recipe.quality.preset) else {
      throw ParcelError.storageError("The video codec is unsupported on this Mac.")
    }
    let duration = try await asset.load(.duration)
    guard duration.isNumeric, duration.seconds > 0 else { throw ParcelError.storageError("The video has no playable duration.") }
    let composition = AVMutableVideoComposition()
    composition.renderSize = size
    composition.frameDuration = CMTime(value: 1, timescale: 30)
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
    let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
    let normalized = transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
      .concatenating(CGAffineTransform(scaleX: size.width / abs(bounds.width), y: size.height / abs(bounds.height)))
    layer.setTransform(normalized, at: .zero)
    instruction.layerInstructions = [layer]
    composition.instructions = [instruction]
    session.videoComposition = composition
    let type: AVFileType = session.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
    guard session.supportedFileTypes.contains(type) else { throw ParcelError.storageError("No compatible video output is available.") }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let output = directory.appendingPathComponent(UUID().uuidString + (type == .mp4 ? ".mp4" : ".mov"))
    var completed = false
    defer { if !completed { try? FileManager.default.removeItem(at: output) } }
    session.outputURL = output; session.outputFileType = type; session.shouldOptimizeForNetworkUse = true
    session.metadata = []
    let cancellation = Task {
      while !Task.isCancelled {
        if token.isCancelled { session.cancelExport(); return }
        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
      }
    }
    defer { cancellation.cancel() }
    try token.check()
    await withCheckedContinuation { continuation in
      session.exportAsynchronously { continuation.resume() }
    }
    try token.check()
    guard session.status == .completed else {
      throw session.error ?? ParcelError.storageError("Video preparation did not complete.")
    }
    let bytes = try FileTree.inspect(output).bytes
    guard bytes > 0 else { throw ParcelError.storageError("The prepared video was empty.") }
    completed = true
    return PreparedVideo(url: output, bytes: bytes,
      description: "Video copy · \(Int(size.width))×\(Int(size.height)) maximum · \(recipe.quality.rawValue) quality")
  }
}
