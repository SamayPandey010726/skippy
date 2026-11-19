import CryptoKit
import Foundation
import Security

enum LicenseStatus: Equatable {
  case development
  case licensed(String)
  case unlicensed, configurationError
  var canUseApp: Bool {
    switch self {
    case .development, .licensed: return true
    default: return false
    }
  }
  var label: String {
    switch self {
    case .development: return "Developer build"
    case .licensed: return "Yours to keep"
    case .unlicensed: return "Licence required"
    case .configurationError: return "Licence setup needed"
    }
  }
}
struct LicensePayload: Codable, Equatable {
  var product: String
  var licenseID: String
  var customer: String
  var issuedAt: Int64
  var expiresAt: Int64?
  var machineID: String?
  var plan: String?
  var deviceLimit: Int?
  var machineIDs: [String]?
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
    guard let publicKey, publicKey.count == 32 else { return .configurationError }
    if let token = read("licence").flatMap({ String(data: $0, encoding: .utf8) }),
      let p = try? verify(token)
    {
      return .licensed(p.customer)
    }
    return .unlicensed
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
    let allowedLimits = ["single": 1, "two": 2, "five": 5]
    if let machines = p.machineIDs {
      guard let plan = p.plan, let expected = allowedLimits[plan], p.deviceLimit == expected,
        !machines.isEmpty, machines.count <= expected, Set(machines).count == machines.count
      else { throw invalid("This licence has an invalid Mac allowance.") }
      guard machines.contains(MachineID.current) else {
        throw invalid("This licence was issued for different Macs, so it can't be used here.")
      }
    } else if p.machineID == nil {
      throw invalid("This licence is not assigned to a Mac.")
    }
    return p
  }
  static func decode(_ s: String) -> Data? {
    var base = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    base += String(repeating: "=", count: (4 - base.count % 4) % 4)
    return Data(base64Encoded: base)
  }
}
