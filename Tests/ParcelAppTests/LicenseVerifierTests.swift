import CryptoKit
import XCTest
@testable import ParcelApp

final class LicenseVerifierTests: XCTestCase {
  func testUnlicensedProductionStateCannotUseApp() {
    XCTAssertFalse(LicenseStatus.unlicensed.canUseApp)
    XCTAssertFalse(LicenseStatus.configurationError.canUseApp)
    XCTAssertTrue(LicenseStatus.licensed("Buyer").canUseApp)
  }

  func testSignedPlanWorksOnlyOnIncludedMac() throws {
    let key = Curve25519.Signing.PrivateKey()
    let payload = LicensePayload(product: "parcel", licenseID: "order-1", customer: "Buyer",
      issuedAt: 1, expiresAt: nil, machineID: nil, plan: "two", deviceLimit: 2,
      machineIDs: [MachineID.current, "another-mac"])
    let token = try signed(payload, key: key)
    XCTAssertEqual(try LicenseVerifier.verify(token, publicKey: key.publicKey.rawRepresentation), payload)
  }

  func testRejectsWrongMacAndInvalidAllowance() throws {
    let key = Curve25519.Signing.PrivateKey()
    var payload = LicensePayload(product: "parcel", licenseID: "order-2", customer: "Buyer",
      issuedAt: 1, expiresAt: nil, machineID: nil, plan: "single", deviceLimit: 1,
      machineIDs: ["another-mac"])
    XCTAssertThrowsError(try LicenseVerifier.verify(try signed(payload, key: key), publicKey: key.publicKey.rawRepresentation))
    payload.machineIDs = [MachineID.current, "another-mac"]
    XCTAssertThrowsError(try LicenseVerifier.verify(try signed(payload, key: key), publicKey: key.publicKey.rawRepresentation))
  }

  private func signed(_ payload: LicensePayload, key: Curve25519.Signing.PrivateKey) throws -> String {
    let message = try JSONEncoder().encode(payload)
    return base64(message) + "." + base64(try key.signature(for: message))
  }

  private func base64(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }
}
