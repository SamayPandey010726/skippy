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
  public init(
    id: UUID = UUID(), sourcePath: String, bookmark: Data? = nil, displayName: String,
    isDirectory: Bool = false, byteCount: Int64 = 0
  ) {
    self.id = id
    self.sourcePath = sourcePath
    self.bookmark = bookmark
    self.displayName = displayName
    self.isDirectory = isDirectory
    self.byteCount = byteCount
    addedAt = Date()
  }
  public var sourceURL: URL { URL(fileURLWithPath: sourcePath) }
  public var effectiveURL: URL { URL(fileURLWithPath: preparedPath ?? sourcePath) }
  public var effectiveBytes: Int64 { preparedBytes ?? byteCount }
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
  public init(name: String) { self.name = name }
  public var totalBytes: Int64 { items.reduce(0) { $0 + $1.effectiveBytes } }
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
  public var includeManifest = true
  public var appendDate = false
  public var compressArchive = true
  public init() {}
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
