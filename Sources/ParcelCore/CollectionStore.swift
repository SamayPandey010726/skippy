import Foundation

public struct TrashedParcel: Codable, Identifiable, Equatable, Sendable {
  public var box: ParcelBox
  public var deletedAt: Date
  public var id: UUID { box.id }
  public var expiresAt: Date { deletedAt.addingTimeInterval(30 * 24 * 60 * 60) }
  public init(box: ParcelBox, deletedAt: Date = Date()) {
    self.box = box
    self.deletedAt = deletedAt
  }
}

public struct CollectionDocument: Codable, Sendable {
  public var version = 1
  public var selectedBox: UUID?
  public var boxes: [ParcelBox]
  public var trashedBoxes: [TrashedParcel]
  public init(boxes: [ParcelBox], selectedBox: UUID?, trashedBoxes: [TrashedParcel] = []) {
    self.boxes = boxes
    self.selectedBox = selectedBox
    self.trashedBoxes = trashedBoxes
  }
  private enum CodingKeys: String, CodingKey { case version, selectedBox, boxes, trashedBoxes }
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decode(Int.self, forKey: .version)
    selectedBox = try container.decodeIfPresent(UUID.self, forKey: .selectedBox)
    boxes = try container.decode([ParcelBox].self, forKey: .boxes)
    trashedBoxes = try container.decodeIfPresent([TrashedParcel].self, forKey: .trashedBoxes) ?? []
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
