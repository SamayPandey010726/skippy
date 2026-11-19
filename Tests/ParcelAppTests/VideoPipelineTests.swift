import AVFoundation
import ParcelCore
import XCTest
@testable import ParcelApp

final class VideoPipelineTests: XCTestCase {
  func testVideoDimensionsRespectPortraitAndDoNotUpscale() {
    XCTAssertEqual(VideoPipeline.outputSize(source: CGSize(width: 1080, height: 1920), maximum: 720), CGSize(width: 404, height: 720))
    XCTAssertEqual(VideoPipeline.outputSize(source: CGSize(width: 64, height: 48), maximum: 720), CGSize(width: 64, height: 48))
    XCTAssertEqual(VideoPipeline.outputSize(source: .zero, maximum: 720), .zero)
  }
  func testRealVideoExportPreservesOriginalAndCancelledExportProducesNothing() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let input = folder.appendingPathComponent("fixture.mov")
    let writer = try AVAssetWriter(outputURL: input, fileType: .mov)
    let stream = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: 64, AVVideoHeightKey: 48])
    let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: stream,
      sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 48])
    writer.add(stream)
    XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime: .zero)
    for index in 0..<12 {
      for _ in 0..<100 {
        if stream.isReadyForMoreMediaData { break }
        try await Task.sleep(for: .milliseconds(10))
      }
      XCTAssertTrue(stream.isReadyForMoreMediaData)
      var pixel: CVPixelBuffer?
      XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 48, kCVPixelFormatType_32ARGB, nil, &pixel), kCVReturnSuccess)
      let buffer = try XCTUnwrap(pixel)
      CVPixelBufferLockBaseAddress(buffer, [])
      memset(CVPixelBufferGetBaseAddress(buffer), 90, CVPixelBufferGetDataSize(buffer))
      CVPixelBufferUnlockBaseAddress(buffer, [])
      XCTAssertTrue(adapter.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 12)))
    }
    stream.markAsFinished(); await writer.finishWriting()
    XCTAssertEqual(writer.status, .completed)
    let original = try Data(contentsOf: input)
    let outputDirectory = folder.appendingPathComponent("prepared")
    let cancelled = CancellationToken(); cancelled.cancel()
    do {
      _ = try await VideoPipeline.prepare(source: input, recipe: VideoRecipe(), token: cancelled, directory: outputDirectory)
      XCTFail("Cancelled preparation must fail")
    } catch { XCTAssertEqual(error as? ParcelError, .cancelled) }
    let output = try await VideoPipeline.prepare(source: input,
      recipe: VideoRecipe(maximumDimension: 480, quality: .high), token: CancellationToken(), directory: outputDirectory)
    XCTAssertGreaterThan(output.bytes, 0)
    XCTAssertNotEqual(output.url, input)
    XCTAssertEqual(try Data(contentsOf: input), original)
    let tracks = try await AVURLAsset(url: output.url).loadTracks(withMediaType: .video)
    let size = try await XCTUnwrap(tracks.first).load(.naturalSize)
    XCTAssertLessThanOrEqual(size.width, 64); XCTAssertLessThanOrEqual(size.height, 48)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path).count, 1)
  }
}
