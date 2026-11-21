import Foundation

public enum ParcelError: LocalizedError, Equatable {
  case invalidName(String)
  case missingSource(String)
  case unsupportedSource(String)
  case sourceChanged(String)
  case existingDestination, cancelled, emptyCollection
  case imageError(String)
  case storageError(String)
  public var errorDescription: String? {
    switch self {
    case .invalidName(let s):
      return "Choose a simple filename without slashes or control characters: \(s)"
    case .missingSource(let s):
      return "The original is unavailable: \(s). Locate it or remove it from the parcel."
    case .unsupportedSource(let s):
      return "\(s) is a link or special file. Add the actual file or folder instead."
    case .sourceChanged(let s):
      return "\(s) changed while being copied. Please try again when it has finished saving."
    case .existingDestination:
      return "A file already exists at that destination. Choose a new name."
    case .cancelled: return "Cancelled. Your originals are unchanged."
    case .emptyCollection: return "Add a file before sealing your parcel."
    case .imageError(let s), .storageError(let s): return s
    }
  }
}

public struct ParcelItem: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var sourcePath: String
  public var bookmark: Data?
  public var displayName: String
  public var isDirectory: Bool
  public var byteCount: Int64
  public var addedAt: Date
  public var preparedPath: String?
  public var preparedBytes: Int64?
  public var preparedDescription: String?
  public var inlineText: String?
  public var stackID: UUID?
  public var stackName: String?
  /// Pinned items survive the self-cleaning auto-clear. Inspired by FlowShelf's pin model.
  public var isPinned: Bool
  public init(
    id: UUID = UUID(), sourcePath: String, bookmark: Data? = nil, displayName: String,
    isDirectory: Bool = false, byteCount: Int64 = 0, isPinned: Bool = false
  ) {
    self.id = id
    self.sourcePath = sourcePath
    self.bookmark = bookmark
    self.displayName = displayName
    self.isDirectory = isDirectory
    self.byteCount = byteCount
    self.isPinned = isPinned
    stackID = nil
    addedAt = Date()
  }
  private enum CodingKeys: String, CodingKey {
    case id, sourcePath, bookmark, displayName, isDirectory, byteCount, addedAt
    case preparedPath, preparedBytes, preparedDescription, isPinned, inlineText, stackID, stackName
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    sourcePath = try c.decode(String.self, forKey: .sourcePath)
    bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
    displayName = try c.decode(String.self, forKey: .displayName)
    isDirectory = try c.decode(Bool.self, forKey: .isDirectory)
    byteCount = try c.decode(Int64.self, forKey: .byteCount)
    addedAt = try c.decode(Date.self, forKey: .addedAt)
    preparedPath = try c.decodeIfPresent(String.self, forKey: .preparedPath)
    preparedBytes = try c.decodeIfPresent(Int64.self, forKey: .preparedBytes)
    preparedDescription = try c.decodeIfPresent(String.self, forKey: .preparedDescription)
    inlineText = try c.decodeIfPresent(String.self, forKey: .inlineText)
    stackID = try c.decodeIfPresent(UUID.self, forKey: .stackID)
    stackName = try c.decodeIfPresent(String.self, forKey: .stackName)
    isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
  }
  public var sourceURL: URL { URL(fileURLWithPath: sourcePath) }
  public var effectiveURL: URL { URL(fileURLWithPath: preparedPath ?? sourcePath) }
  public var effectiveBytes: Int64 { preparedBytes ?? byteCount }
  public var isInlineText: Bool { inlineText != nil }
  public var compactDisplayName: String {
    let stem = (effectiveName as NSString).deletingPathExtension
    let words = stem.split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" })
    guard words.count > 2 || effectiveName.count > 20 else { return effectiveName }
    return words.prefix(2).joined(separator: " ") + "…"
  }
  public var effectiveName: String {
    guard let path = preparedPath else { return displayName }
    let ext = URL(fileURLWithPath: path).pathExtension
    let base = (displayName as NSString).deletingPathExtension
    return ext.isEmpty ? base : base + "." + ext
  }
}

public struct ParcelBox: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID = UUID()
  public var name: String
  public var createdAt = Date()
  public var updatedAt = Date()
  public var items: [ParcelItem] = []
  public var note = ""
  public var lastArchivePath: String?
  public var isPinned: Bool?
  public init(name: String) { self.name = name }
  public var totalBytes: Int64 { items.reduce(0) { $0 + $1.effectiveBytes } }
  public var isShelfPinned: Bool { isPinned ?? items.contains(where: \.isPinned) }
}

public enum ImageFormat: String, Codable, CaseIterable, Sendable {
  case original, jpeg, png, heic
  public var label: String {
    switch self {
    case .original: return "Keep format"
    case .jpeg: return "JPEG"
    case .png: return "PNG"
    case .heic: return "HEIC"
    }
  }
}
public struct ImageRecipe: Codable, Equatable, Sendable {
  public var format: ImageFormat = .jpeg
  public var quality: Double = 0.82
  public var maximumDimension: Int = 2400
  public var removeMetadata = true
  public var flattenTransparency = false
  public init() {}
}
public struct PackagingOptions: Codable, Equatable, Sendable {
  public var cleanMacMetadata = true
  public var includeManifest = false  // Shreyash: basic ZIP stays; manifest emphasis removed.
  public var appendDate = false
  public var compressArchive = true
  public var format: PackFormat = .zip
  public var strength: PackStrength = .balanced
  public var saveToDesktop = false
  public init() {}
  public static func load() -> PackagingOptions {
    guard let data = UserDefaults.standard.data(forKey: "parcel-packaging-options"),
      let o = try? JSONDecoder().decode(PackagingOptions.self, from: data)
    else { return PackagingOptions() }
    // RAR's installer is Gatekeeper-blocked: fall back to ZIP when the tool
    // isn't on the Mac.
    if o.format == .rar, !o.format.isUsable {
      var normalized = o
      normalized.format = .zip
      return normalized
    }
    return o
  }
  public func save() {
    if let data = try? JSONEncoder().encode(self) {
      UserDefaults.standard.set(data, forKey: "parcel-packaging-options")
    }
  }
}

/// Archive formats Parcel can pack. ZIP is built in; 7z and RAR use the
/// matching command-line tool when it is installed on the Mac.
public enum PackFormat: String, Codable, CaseIterable, Sendable {
  case zip, sevenZip, rar
  public var label: String {
    switch self {
    case .zip: return "ZIP"
    case .sevenZip: return "7z"
    case .rar: return "RAR"
    }
  }
  public var fileExtension: String {
    switch self {
    case .zip: return "zip"
    case .sevenZip: return "7z"
    case .rar: return "rar"
    }
  }
  /// RAR's installer is blocked by macOS Gatekeeper (Homebrew disabled the
  /// cask), so it is only offered when the tool is already on the Mac.
  /// Everything else installs from inside the app.
  public static var availableCases: [PackFormat] {
    var cases: [PackFormat] = [.zip, .sevenZip]
    if ExternalArchiver.toolPath(for: .rar) != nil { cases.append(.rar) }
    return cases
  }
  /// True when picking this format can actually pack right now.
  public var isUsable: Bool {
    self == .zip || ExternalArchiver.toolPath(for: self) != nil
  }
}

/// How hard the packer squeezes. Light is fastest, heavy is smallest.
public enum PackStrength: String, Codable, CaseIterable, Sendable {
  case light, balanced, heavy
  public var label: String {
    switch self {
    case .light: return "Light"
    case .balanced: return "Balanced"
    case .heavy: return "Heavy"
    }
  }
  public var hint: String {
    switch self {
    case .light: return "Fastest, larger file"
    case .balanced: return "A good middle"
    case .heavy: return "Smallest, takes longer"
    }
  }
}
public struct PackageInput: Sendable {
  public var url: URL
  public var desiredName: String
  public var originalBytes: Int64
  public init(url: URL, desiredName: String, originalBytes: Int64 = 0) {
    self.url = url
    self.desiredName = desiredName
    self.originalBytes = originalBytes
  }
}
public struct ManifestEntry: Codable, Equatable, Sendable {
  public let name: String
  public let bytes: Int64
  public let folder: Bool
  public init(name: String, bytes: Int64, folder: Bool) {
    self.name = name
    self.bytes = bytes
    self.folder = folder
  }
}
public struct PackageResult: Sendable {
  public var archive: URL
  public var entries: [ManifestEntry]
  public var bytes: Int64
  public var manifestText: String
}
public final class CancellationToken: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false
  private var currentProgress: Progress?
  public init() {}
  public func cancel() {
    lock.lock()
    value = true
    let p = currentProgress
    lock.unlock()
    p?.cancel()
  }
  public var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
  public func check() throws { if isCancelled { throw ParcelError.cancelled } }
  public func track(_ progress: Progress?) {
    lock.lock()
    currentProgress = progress
    let cancelled = value
    lock.unlock()
    if cancelled { progress?.cancel() }
  }
}
