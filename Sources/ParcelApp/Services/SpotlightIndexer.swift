import Combine
@preconcurrency import CoreSpotlight
import Foundation
import ParcelCore
import UniformTypeIdentifiers

struct SpotlightParcelRecord: Equatable, Sendable {
  let identifier: String
  let title: String
  let description: String
  let keywords: [String]
  let url: URL
}

enum SpotlightParcelContent {
  static let domain = "com.yourcompany.parcel.library"

  static func records(for boxes: [ParcelBox]) -> [SpotlightParcelRecord] {
    boxes.map { box in
      let names = box.items.map(\.effectiveName)
      let description = names.isEmpty
        ? "Empty parcel"
        : names.prefix(8).joined(separator: ", ") + (names.count > 8 ? " and \(names.count - 8) more" : "")
      let extensions = Set(names.compactMap { name -> String? in
        let ext = (name as NSString).pathExtension.lowercased()
        return ext.isEmpty ? nil : ext
      })
      return SpotlightParcelRecord(
        identifier: box.id.uuidString, title: box.name, description: description,
        keywords: ["Parcel", "files"] + extensions.sorted(),
        url: URL(string: "parcel://open/\(box.id.uuidString)")!)
    }
  }
}

@MainActor final class SpotlightIndexer: ObservableObject {
  static let shared = SpotlightIndexer()
  @Published var enabled: Bool {
    didSet {
      defaults.set(enabled, forKey: key)
      if enabled { scheduleCurrent() } else { clear() }
    }
  }
  private weak var store: ParcelStore?
  private var observer: AnyCancellable?
  private var indexedIDs = Set<String>()
  private var rebuiltExistingIndex = false
  private let defaults: UserDefaults
  private let key = "parcel.spotlightIndexEnabled"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    enabled = defaults.object(forKey: key) as? Bool ?? true
  }

  func install(store: ParcelStore) {
    guard self.store == nil else { return }
    self.store = store
    observer = store.$boxes
      .debounce(for: .milliseconds(450), scheduler: RunLoop.main)
      .sink { [weak self] boxes in self?.index(boxes) }
    if enabled { index(store.boxes) }
  }

  private func scheduleCurrent() {
    guard let store else { return }
    index(store.boxes)
  }

  private func index(_ boxes: [ParcelBox]) {
    guard enabled else { return }
    let records = SpotlightParcelContent.records(for: boxes)
    let nextIDs = Set(records.map(\.identifier))
    let removed = Array(indexedIDs.subtracting(nextIDs))
    if !removed.isEmpty { CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: removed) }
    let items = records.map { record -> CSSearchableItem in
      let attributes = CSSearchableItemAttributeSet(contentType: .item)
      attributes.title = record.title
      attributes.displayName = record.title
      attributes.contentDescription = record.description
      attributes.keywords = record.keywords
      attributes.contentURL = record.url
      return CSSearchableItem(
        uniqueIdentifier: record.identifier, domainIdentifier: SpotlightParcelContent.domain,
        attributeSet: attributes)
    }
    let index = CSSearchableIndex.default()
    if !rebuiltExistingIndex {
      rebuiltExistingIndex = true
      index.deleteSearchableItems(withDomainIdentifiers: [SpotlightParcelContent.domain]) { error in
        guard error == nil else { return }
        index.indexSearchableItems(items)
      }
    } else {
      index.indexSearchableItems(items)
    }
    indexedIDs = nextIDs
  }

  private func clear() {
    CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [SpotlightParcelContent.domain])
    indexedIDs.removeAll()
    rebuiltExistingIndex = false
  }
}
