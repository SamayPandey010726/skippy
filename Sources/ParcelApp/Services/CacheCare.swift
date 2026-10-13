import Foundation
import ParcelCore

enum CacheCare {
  static func removeUnused(boxes: [ParcelBox], olderThan date: Date) throws -> Int {
    let references = boxes.flatMap { box -> [URL] in
      box.items.flatMap {
        [$0.sourceURL] + ($0.preparedPath.map { [URL(fileURLWithPath: $0)] } ?? [])
      }
        + (box.lastArchivePath.map { [URL(fileURLWithPath: $0)] } ?? [])
    }
    var removed = 0
    for directory in [StoragePaths.prepared, StoragePaths.received, StoragePaths.exports] {
      for child in try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
      {
        if references.contains(where: {
          FileTree.isInside($0, directory: child) || FileTree.isInside(child, directory: $0)
        }) {
          continue
        }
        let values = try child.resourceValues(forKeys: [.contentModificationDateKey])
        guard let modified = values.contentModificationDate, modified < date else { continue }
        if StoragePaths.deleteOwned(child) { removed += 1 }
      }
    }
    return removed
  }
}
