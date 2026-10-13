import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import ParcelCore
import UniformTypeIdentifiers

@main enum MacSmoke {
  static func require(_ condition: Bool, _ message: String) throws {
    if !condition {
      throw NSError(domain: "ParcelSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
  }
  static func fixture(at url: URL, transparent: Bool, jpeg: Bool = false) throws {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard
      let context = CGContext(
        data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let target = CGImageDestinationCreateWithURL(
        url as CFURL, (jpeg ? UTType.jpeg.identifier : UTType.png.identifier) as CFString, 1, nil)
    else { throw NSError(domain: "Fixture", code: 1) }
    if !transparent {
      context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
    }
    context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.3, alpha: 1))
    context.fill(CGRect(x: 20, y: 20, width: 200, height: 160))
    let props: [CFString: Any] = [
      kCGImagePropertyGPSDictionary: [
        kCGImagePropertyGPSLatitude: 37.3, kCGImagePropertyGPSLatitudeRef: "N",
      ]
    ]
    CGImageDestinationAddImage(target, context.makeImage()!, props as CFDictionary)
    try require(CGImageDestinationFinalize(target), "Fixture write failed")
  }
  @MainActor static func main() throws {
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Parcel-mac-check-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    try StoragePaths.createDirectories()
    let source = scratch.appendingPathComponent("opaque.png")
    try fixture(at: source, transparent: false)
    let originalBytes = try Data(contentsOf: source)
    var recipe = ImageRecipe()
    recipe.maximumDimension = 320
    recipe.format = .jpeg
    let result = try ImagePipeline.prepare(
      source: source, recipe: recipe, token: CancellationToken())
    defer { StoragePaths.deleteOwned(result.url) }
    try require(try Data(contentsOf: source) == originalBytes, "The original changed")
    try require(result.width == 320 && result.height == 240, "Resize dimensions are wrong")
    let imageSource = CGImageSourceCreateWithURL(result.url as CFURL, nil)!
    let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as! [CFString: Any]
    try require(properties[kCGImagePropertyGPSDictionary] == nil, "GPS was not removed")
    let gpsSource = scratch.appendingPathComponent("gps.jpg")
    try fixture(at: gpsSource, transparent: false, jpeg: true)
    let gpsInput = CGImageSourceCreateWithURL(gpsSource as CFURL, nil)!
    let gpsOriginal = CGImageSourceCopyPropertiesAtIndex(gpsInput, 0, nil) as! [CFString: Any]
    try require(
      gpsOriginal[kCGImagePropertyGPSDictionary] != nil, "Fixture must actually contain GPS")
    let stripped = try ImagePipeline.prepare(
      source: gpsSource, recipe: recipe, token: CancellationToken())
    defer { StoragePaths.deleteOwned(stripped.url) }
    let strippedSource = CGImageSourceCreateWithURL(stripped.url as CFURL, nil)!
    let strippedProps =
      CGImageSourceCopyPropertiesAtIndex(strippedSource, 0, nil) as! [CFString: Any]
    try require(
      strippedProps[kCGImagePropertyGPSDictionary] == nil, "GPS was not removed from JPEG")
    let alpha = scratch.appendingPathComponent("alpha.png")
    try fixture(at: alpha, transparent: true)
    var rejected = false
    do {
      _ = try ImagePipeline.prepare(source: alpha, recipe: recipe, token: CancellationToken())
    } catch { rejected = true }
    try require(rejected, "Transparent JPEG was not rejected")
    recipe.flattenTransparency = true
    let flattened = try ImagePipeline.prepare(
      source: alpha, recipe: recipe, token: CancellationToken())
    defer { StoragePaths.deleteOwned(flattened.url) }
    recipe.format = .png
    recipe.flattenTransparency = false
    let png = try ImagePipeline.prepare(source: alpha, recipe: recipe, token: CancellationToken())
    defer { StoragePaths.deleteOwned(png.url) }
    let token = CancellationToken()
    token.cancel()
    rejected = false
    do { _ = try ImagePipeline.prepare(source: source, recipe: recipe, token: token) } catch {
      rejected = true
    }
    try require(rejected, "Cancelled image job did not stop")
    let key = Curve25519.Signing.PrivateKey()
    let payload = Data(
      "{\"product\":\"parcel\",\"licenseID\":\"smoke\",\"customer\":\"Test\",\"issuedAt\":1,\"expiresAt\":null}"
        .utf8)
    func b64(_ data: Data) -> String {
      data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(
        of: "/", with: "_"
      ).replacingOccurrences(of: "=", with: "")
    }
    let signature = try key.signature(for: payload)
    let licence = b64(payload) + "." + b64(signature)
    let verified = try LicenseVerifier.verify(licence, publicKey: key.publicKey.rawRepresentation)
    try require(verified.customer == "Test", "Signed licence failed")
    rejected = false
    do {
      _ = try LicenseVerifier.verify(
        licence, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)
    } catch { rejected = true }
    try require(rejected, "Wrong-key licence was accepted")
    print(
      "PASS: native image resize, opaque PNG→JPEG, GPS removal, transparency guard, PNG export, cancellation and licence signatures."
    )
  }
}
