import CoreGraphics
import Foundation
import ImageIO
import ParcelCore
import UniformTypeIdentifiers

struct PreparedImage: Sendable {
  var url: URL
  var bytes: Int64
  var width: Int
  var height: Int
  var description: String
}
enum ImagePipeline {
  static func canPrepare(_ url: URL) -> Bool {
    ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "webp", "avif"].contains(
      url.pathExtension.lowercased())
  }
  static func prepare(
    source: URL, recipe: ImageRecipe, token: CancellationToken, outputName: String? = nil
  ) throws
    -> PreparedImage
  {
    try token.check()
    guard (0.1...1).contains(recipe.quality),
      recipe.maximumDimension == 0 || (320...12000).contains(recipe.maximumDimension)
    else {
      throw ParcelError.imageError("Choose a valid quality and image size.")
    }
    let fm = FileManager.default
    let scratch = fm.temporaryDirectory.appendingPathComponent(
      "Parcel-image-" + UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: scratch) }
    let snapshot = scratch.appendingPathComponent(source.lastPathComponent)
    _ = try CoordinatedFiles.read(source) { actual in
      try FileTree.copy(actual, to: snapshot, cleanMetadata: false, token: token)
    }
    guard
      let input = CGImageSourceCreateWithURL(
        snapshot as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
    else {
      throw ParcelError.imageError("This image could not be decoded: \(source.lastPathComponent)")
    }
    guard CGImageSourceGetCount(input) == 1 else {
      throw ParcelError.imageError(
        "Animated or multi-page images must be sent as originals. \(source.lastPathComponent) was left unchanged."
      )
    }
    let original = CGImageSourceCopyPropertiesAtIndex(input, 0, nil) as? [CFString: Any] ?? [:]
    let width = (original[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
    let height = (original[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
    let maximum =
      recipe.maximumDimension == 0
      ? max(width, height) : min(recipe.maximumDimension, max(width, height))
    guard width > 0, height > 0, maximum > 0, maximum <= 12000 else {
      throw ParcelError.imageError(
        "Choose a smaller maximum size for this image. The full-size decode would be too large.")
    }
    let scale = min(1, Double(maximum) / Double(max(width, height)))
    guard Double(width) * Double(height) * scale * scale <= 50_000_000 else {
      throw ParcelError.imageError(
        "Choose a smaller maximum size to keep image processing memory bounded.")
    }
    let opts: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maximum,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard var image = CGImageSourceCreateThumbnailAtIndex(input, 0, opts as CFDictionary) else {
      throw ParcelError.imageError("Could not resize this image.")
    }
    try token.check()
    let ext = source.pathExtension.lowercased()
    let format: ImageFormat
    if recipe.format == .original {
      switch ext {
      case "png": format = .png
      case "heic", "heif": format = .heic
      case "jpg", "jpeg": format = .jpeg
      default:
        throw ParcelError.imageError(
          "Keep format supports JPEG, PNG and HEIC. Choose an explicit output format for \(source.lastPathComponent)."
        )
      }
    } else {
      format = recipe.format
    }
    let alpha = [.first, .last, .premultipliedFirst, .premultipliedLast].contains(image.alphaInfo)
    // Normalise orientation and colours in a bounded sRGB destination canvas.
    guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          | CGBitmapInfo.byteOrder32Big.rawValue)
    else {
      throw ParcelError.imageError("Could not allocate a safe image canvas.")
    }
    if format == .jpeg && recipe.flattenTransparency {
      context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    if format == .jpeg && alpha && !recipe.flattenTransparency,
      let pixels = context.data?.assumingMemoryBound(to: UInt8.self)
    {
      var transparent = false
      for y in 0..<image.height {
        for x in 0..<image.width where pixels[y * context.bytesPerRow + x * 4 + 3] < 255 {
          transparent = true
          break
        }
        if transparent { break }
      }
      if transparent {
        throw ParcelError.imageError(
          "\(source.lastPathComponent) has transparency. Choose PNG/HEIC, or explicitly enable a white background for JPEG."
        )
      }
    }
    guard let normalized = context.makeImage() else {
      throw ParcelError.imageError("Could not render the prepared copy.")
    }
    image = normalized
    let type =
      format == .png
      ? UTType.png.identifier : format == .heic ? UTType.heic.identifier : UTType.jpeg.identifier
    guard (CGImageDestinationCopyTypeIdentifiers() as? [String])?.contains(type) == true else {
      throw ParcelError.imageError(
        "\(format.label) encoding is not available on this Mac. Choose JPEG or PNG.")
    }
    let outputFolder = StoragePaths.prepared.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: outputFolder, withIntermediateDirectories: true)
    let namedSource = URL(fileURLWithPath: outputName ?? source.lastPathComponent)
    let stem = NamePolicy.safeArchiveStem(namedSource.deletingPathExtension().lastPathComponent)
    let output = outputFolder.appendingPathComponent(stem)
      .appendingPathExtension(format == .jpeg ? "jpg" : format.rawValue)
    var succeeded = false
    defer { if !succeeded { try? fm.removeItem(at: outputFolder) } }
    guard
      let destination = CGImageDestinationCreateWithURL(output as CFURL, type as CFString, 1, nil)
    else {
      throw ParcelError.imageError("Could not create the prepared image.")
    }
    var properties = recipe.removeMetadata ? [:] : original
    properties.removeValue(forKey: kCGImagePropertyPixelWidth)
    properties.removeValue(forKey: kCGImagePropertyPixelHeight)
    properties[kCGImagePropertyOrientation] = 1
    if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
      tiff[kCGImagePropertyTIFFOrientation] = 1
      properties[kCGImagePropertyTIFFDictionary] = tiff
    }
    if format != .png { properties[kCGImageDestinationLossyCompressionQuality] = recipe.quality }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw ParcelError.imageError("The image encoder could not finish. Choose another format.")
    }
    try token.check()
    let bytes = (try fm.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.int64Value ?? 0
    succeeded = true
    return PreparedImage(
      url: output, bytes: bytes, width: image.width, height: image.height,
      description: "\(format.label) · \(image.width) × \(image.height)")
  }
}
