import XCTest
import CryptoKit
@testable import NIVQOProtocol

final class FlowProtocolTests: XCTestCase {
    func fixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "node-flow-v1", withExtension: "json", subdirectory: "Fixtures"))
        return try FlowProtocol.object(Data(contentsOf: url))
    }
    func testNodeCryptographicInteroperability() throws {
        let f = try fixture()
        func decode(_ name: String, _ limit: Int) throws -> Data { try Data.decodeBase64URL(XCTUnwrap(f[name] as? String), limit: limit) }
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: decode("clientPrivate", 32))
        let keys = try FlowProtocol.derive(privateKey: privateKey, serverSPKI: decode("serverPublic", 44), secret: decode("secret", 32))
        XCTAssertEqual(keys.transmit.withUnsafeBytes { Data($0) }, try decode("clientTransmit", 32))
        XCTAssertEqual(keys.receive.withUnsafeBytes { Data($0) }, try decode("clientReceive", 32))
        XCTAssertEqual(FlowProtocol.proof(keys, role: "client"), try decode("clientProof", 32))
        try FlowProtocol.validateServerProof(XCTUnwrap(f["serverProof"] as? String), keys: keys)
        let frame = try XCTUnwrap(f["serverFrame"] as? [String: Any])
        let payload = try FlowProtocol.open(frame, expectedSequence: 1, key: keys.receive)
        XCTAssertEqual(payload["type"] as? String, "drop-text")
        XCTAssertEqual((payload["data"] as? [String: Any])?["text"] as? String, "NIVQO desktop to iPhone ✓")
        XCTAssertThrowsError(try FlowProtocol.open(frame, expectedSequence: 2, key: keys.receive))
        var tampered = frame; tampered["tag"] = Data(repeating: 0, count: 16).base64URL
        XCTAssertThrowsError(try FlowProtocol.open(tampered, expectedSequence: 1, key: keys.receive))
    }
    func testPairAddressRestrictions() throws {
        let secret = Data(repeating: 5, count: 32).base64URL
        XCTAssertEqual(try PairAddress.parse("nivqo-pair://192.168.1.2:3456/" + secret).host, "192.168.1.2")
        for prefix in ["https://192.168.1.2:3456/", "nivqo-pair://8.8.8.8:3456/", "nivqo-pair://192.168.1.2:0/"] {
            XCTAssertThrowsError(try PairAddress.parse(prefix + secret))
        }
    }
    func testTransferValidation() throws {
        XCTAssertThrowsError(try IncomingTransfer.parse(["type": "flow-tab", "data": ["url": "javascript:alert(1)"]]))
        XCTAssertThrowsError(try IncomingTransfer.parse(["type": "drop-file", "data": ["name": "a", "data": "!!!"]]))
        XCTAssertEqual(safeFileName("../../safe.txt"), "safe.txt")
    }
}
