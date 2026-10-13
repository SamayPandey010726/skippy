import Foundation

public struct CollectionDocument: Codable, Sendable {
  public var version = 1
  public var selectedBox: UUID?
  public var boxes: [ParcelBox]
  public init(boxes: [ParcelBox], selectedBox: UUID?) {
    self.boxes = boxes
    self.selectedBox = selectedBox
  }
}
public enum CollectionStore {
  public static func read(from url: URL) throws -> CollectionDocument {
    let doc = try JSONDecoder().decode(CollectionDocument.self, from: Data(contentsOf: url))
    guard doc.version == 1 else {
      throw ParcelError.storageError(
        "This parcel library was saved by a newer app. Please update Parcel.")
    }
    return doc
  }
  public static func save(_ document: CollectionDocument, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(document).write(to: url, options: .atomic)
  }
}
