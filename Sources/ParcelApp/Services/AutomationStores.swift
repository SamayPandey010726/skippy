import Combine
import Foundation
import ParcelCore

struct ImageTransformPreset: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var name: String
  var recipe: ImageRecipe

  init(id: UUID = UUID(), name: String, recipe: ImageRecipe) {
    self.id = id
    self.name = name
    self.recipe = recipe
  }
}

struct VideoTransformPreset: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var name: String
  var maximumDimension: Int
  var quality: VideoQuality

  init(id: UUID = UUID(), name: String, recipe: VideoRecipe) {
    self.id = id
    self.name = name
    maximumDimension = recipe.maximumDimension
    quality = recipe.quality
  }

  var recipe: VideoRecipe {
    VideoRecipe(maximumDimension: maximumDimension, quality: quality)
  }
}

private struct TransformPresetDocument: Codable {
  var images: [ImageTransformPreset]
  var videos: [VideoTransformPreset]
}

@MainActor final class TransformPresetStore: ObservableObject {
  static let shared = TransformPresetStore()
  @Published private(set) var imagePresets: [ImageTransformPreset]
  @Published private(set) var videoPresets: [VideoTransformPreset]
  private let defaults: UserDefaults
  private let key = "parcel.transformPresets.v1"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: key),
      let document = try? JSONDecoder().decode(TransformPresetDocument.self, from: data) {
      imagePresets = document.images
      videoPresets = document.videos
    } else {
      var web = ImageRecipe()
      web.format = .jpeg; web.quality = 0.76; web.maximumDimension = 1600
      var retina = ImageRecipe()
      retina.format = .png; retina.maximumDimension = 2400
      imagePresets = [
        ImageTransformPreset(name: "Web ready", recipe: web),
        ImageTransformPreset(name: "Retina PNG", recipe: retina),
      ]
      videoPresets = [
        VideoTransformPreset(name: "Message size", recipe: VideoRecipe(maximumDimension: 720, quality: .small)),
        VideoTransformPreset(name: "Balanced 1080p", recipe: VideoRecipe(maximumDimension: 1920, quality: .balanced)),
      ]
      save()
    }
  }

  func addImage(name: String, recipe: ImageRecipe) {
    imagePresets.append(ImageTransformPreset(name: validName(name, fallback: "Image preset"), recipe: normalized(recipe)))
    save()
  }

  func addVideo(name: String, recipe: VideoRecipe) {
    videoPresets.append(VideoTransformPreset(name: validName(name, fallback: "Video preset"), recipe: normalized(recipe)))
    save()
  }

  func update(_ preset: ImageTransformPreset) {
    guard let index = imagePresets.firstIndex(where: { $0.id == preset.id }) else { return }
    var next = preset
    next.name = validName(next.name, fallback: imagePresets[index].name)
    next.recipe = normalized(next.recipe)
    imagePresets[index] = next
    save()
  }

  func update(_ preset: VideoTransformPreset) {
    guard let index = videoPresets.firstIndex(where: { $0.id == preset.id }) else { return }
    var next = preset
    next.name = validName(next.name, fallback: videoPresets[index].name)
    let recipe = normalized(next.recipe)
    next.maximumDimension = recipe.maximumDimension
    next.quality = recipe.quality
    videoPresets[index] = next
    save()
  }

  func removeImage(_ id: UUID) { imagePresets.removeAll { $0.id == id }; save() }
  func removeVideo(_ id: UUID) { videoPresets.removeAll { $0.id == id }; save() }

  private func validName(_ name: String, fallback: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return String((trimmed.isEmpty ? fallback : trimmed).prefix(48))
  }

  private func normalized(_ recipe: ImageRecipe) -> ImageRecipe {
    var next = recipe
    next.quality = min(1, max(0.1, next.quality.isFinite ? next.quality : 0.82))
    if ![0, 1200, 1600, 2400, 3200, 4000].contains(next.maximumDimension) { next.maximumDimension = 2400 }
    return next
  }

  private func normalized(_ recipe: VideoRecipe) -> VideoRecipe {
    VideoRecipe(
      maximumDimension: [480, 720, 1280, 1920, 3840].contains(recipe.maximumDimension) ? recipe.maximumDimension : 1280,
      quality: recipe.quality)
  }

  private func save() {
    let document = TransformPresetDocument(images: imagePresets, videos: videoPresets)
    if let data = try? JSONEncoder().encode(document) { defaults.set(data, forKey: key) }
  }
}

struct RecentParcelAction: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var title: String
  var symbol: String
  var lastUsed: Date
  var useCount: Int
}

@MainActor final class RecentActionStore: ObservableObject {
  static let shared = RecentActionStore()
  @Published private(set) var actions: [RecentParcelAction]
  private let defaults: UserDefaults
  private let key = "parcel.recentActions.v1"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    actions = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([RecentParcelAction].self, from: $0) } ?? []
    actions = Array(actions.sorted { $0.lastUsed > $1.lastUsed }.prefix(8))
  }

  func record(id: String, title: String, symbol: String, at date: Date = Date()) {
    let previous = actions.first { $0.id == id }
    actions.removeAll { $0.id == id }
    actions.insert(RecentParcelAction(
      id: id, title: title, symbol: symbol, lastUsed: date,
      useCount: min(Int.max, (previous?.useCount ?? 0) + 1)), at: 0)
    actions = Array(actions.prefix(8))
    save()
  }

  func prioritize(_ available: [QuickConvertAction]) -> [QuickConvertAction] {
    let rank = Dictionary(uniqueKeysWithValues: actions.enumerated().map { ($0.element.id, $0.offset) })
    return available.enumerated().sorted { lhs, rhs in
      let left = rank["convert.\(lhs.element.rawValue)"] ?? Int.max
      let right = rank["convert.\(rhs.element.rawValue)"] ?? Int.max
      return left == right ? lhs.offset < rhs.offset : left < right
    }.map(\.element)
  }

  func isRecent(_ action: QuickConvertAction) -> Bool {
    actions.first?.id == "convert.\(action.rawValue)"
  }

  private func save() {
    if let data = try? JSONEncoder().encode(actions) { defaults.set(data, forKey: key) }
  }
}
