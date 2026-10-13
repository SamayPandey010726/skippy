import CryptoKit
import Foundation
import Security

enum LicenseStatus: Equatable {
  case development
  case appStore
  case trial(Int)
  case licensed(String)
  case expired, configurationError
  var canUseApp: Bool {
    switch self {
    case .development, .appStore, .trial, .licensed: return true
    default: return false
    }
  }
  var label: String {
    switch self {
    case .development: return "Developer build"
    case .appStore: return "From the App Store"
    case .trial(let days): return "\(days) days to explore"
    case .licensed: return "Yours to keep"
    case .expired: return "Your trial has ended"
    case .configurationError: return "Licence setup needed"
    }
  }
}
struct LicensePayload: Codable {
  var product: String
  var licenseID: String
  var customer: String
  var issuedAt: Int64
  var expiresAt: Int64?
  /// Fingerprint of the Mac this licence was issued for. Nil = portable key (legacy).
  var machineID: String?
}
/// Stable, privacy-preserving fingerprint of this Mac. A licence issued for
/// this value will not validate on any other machine, so keys can't be shared.
enum MachineID {
  static var current: String {
    let seed: String = {
      var raw: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
      var ts = timespec(tv_sec: 0, tv_nsec: 0)
      if gethostuuid(&raw, &ts) == 0 { return UUID(uuid: raw).uuidString }
      if let saved = UserDefaults.standard.string(forKey: "parcel.machineSeed") { return saved }
      let fresh = UUID().uuidString
      UserDefaults.standard.set(fresh, forKey: "parcel.machineSeed")
      return fresh
    }()
    let digest = SHA256.hash(data: Data(("parcel-machine-v1:" + seed).utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
private struct TrialRecord: Codable {
  var firstSeen: Date
  var latestSeen: Date
}
@MainActor final class LicenseManager {
  static let shared = LicenseManager()
  private let service = "app.parcel.licence"
  private var publicKey: Data? {
    guard let text = Bundle.main.object(forInfoDictionaryKey: "ParcelLicensePublicKey") as? String
    else { return nil }
    return Data(base64Encoded: text)
  }
  private var development: Bool {
    Bundle.main.object(forInfoDictionaryKey: "ParcelDevelopmentMode") as? Bool ?? true
  }
  func status() -> LicenseStatus {
    if development { return .development }
    if isAppStorePurchase { return .appStore }
    guard let publicKey, publicKey.count == 32 else { return .configurationError }
    if let token = read("licence").flatMap({ String(data: $0, encoding: .utf8) }),
      let p = try? verify(token)
    {
      return .licensed(p.customer)
    }
    let now = Date()
    var record =
      read("trial").flatMap { try? JSONDecoder().decode(TrialRecord.self, from: $0) }
      ?? TrialRecord(firstSeen: now, latestSeen: now)
    if now < record.latestSeen.addingTimeInterval(-3600) { return .expired }
    record.latestSeen = max(now, record.latestSeen)
    guard let data = try? JSONEncoder().encode(record), write(data, account: "trial") else {
      return .configurationError
    }
    let days = 14 - Int(now.timeIntervalSince(record.firstSeen) / 86400)
    return days > 0 ? .trial(days) : .expired
  }
  func activate(_ token: String) throws {
    let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
    _ = try verify(clean)
    guard write(Data(clean.utf8), account: "licence") else {
      throw NSError(
        domain: "Parcel", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Your licence could not be saved in Keychain."])
    }
  }
  /// Mac App Store builds always carry a receipt; direct-download builds never
  /// do. Apple ties the purchase to the buyer's Apple ID, so no licence key is
  /// needed on this channel. Production hardening: full receipt signature
  /// validation per Apple's docs — presence is the v1 gate.
  private var isAppStorePurchase: Bool {
    guard let url = Bundle.main.appStoreReceiptURL else { return false }
    return FileManager.default.fileExists(atPath: url.path)
  }
  private func verify(_ token: String) throws -> LicensePayload {
    guard let publicKey else {
      throw NSError(
        domain: "Parcel", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey: "Licence verification is not configured in this build."
        ])
    }
    return try LicenseVerifier.verify(token, publicKey: publicKey)
  }
  private func decode(_ s: String) -> Data? {
    LicenseVerifier.decode(s)
  }
  private func read(_ account: String) -> Data? {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
      kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
    return result as? Data
  }
  private func write(_ data: Data, account: String) -> Bool {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
    ]
    let update: [CFString: Any] = [kSecValueData: data]
    let result = SecItemUpdate(query as CFDictionary, update as CFDictionary)
    if result == errSecSuccess { return true }
    guard result == errSecItemNotFound else { return false }
    var add = query
    add[kSecValueData] = data
    add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
  }
}
enum LicenseVerifier {
  static func verify(_ token: String, publicKey: Data, at now: Date = Date()) throws
    -> LicensePayload
  {
    func invalid(_ why: String) -> NSError {
      NSError(domain: "Parcel", code: 2, userInfo: [NSLocalizedDescriptionKey: why])
    }
    let pieces = token.split(separator: ".", omittingEmptySubsequences: false)
    guard pieces.count == 2, let message = decode(String(pieces[0])),
      let signature = decode(String(pieces[1])),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
      key.isValidSignature(signature, for: message),
      let p = try? JSONDecoder().decode(LicensePayload.self, from: message), p.product == "parcel",
      !p.licenseID.isEmpty
    else {
      throw invalid(
        "This licence could not be verified. Check that you pasted the complete Parcel licence.")
    }
    if let expiry = p.expiresAt, Int64(now.timeIntervalSince1970) > expiry {
      throw invalid("This licence has expired.")
    }
    if let bound = p.machineID, bound != MachineID.current {
      throw invalid("This licence was issued for a different Mac, so it can't be used here.")
    }
    return p
  }
  static func decode(_ s: String) -> Data? {
    var base = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    base += String(repeating: "=", count: (4 - base.count % 4) % 4)
    return Data(base64Encoded: base)
  }
}
