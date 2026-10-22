import Foundation
import CryptoKit
import CoreFoundation

enum FlowError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

struct PairAddress {
    let host: String
    let port: UInt16
    let secret: Data

    static func parse(_ text: String) throws -> PairAddress {
        let code = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^nivqo-pair://([0-9]{1,3}(?:\.[0-9]{1,3}){3}):([0-9]{1,5})/([A-Za-z0-9_-]{43})$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let whole = NSRange(code.startIndex..., in: code)
        guard let match = regex.firstMatch(in: code, range: whole), match.range == whole else {
            throw FlowError.invalid("Use a complete NIVQO pairing code or scan the desktop QR code.")
        }
        func part(_ n: Int) -> String { String(code[Range(match.range(at: n), in: code)!]) }
        let host = part(1), octets = host.split(separator: ".")
        guard octets.allSatisfy({ token in
            guard let number = UInt8(token) else { return false }
            return String(number) == token
        }), let port = UInt16(part(2)), port > 0 else { throw FlowError.invalid("Invalid LAN address or port.") }
        let numbers = octets.map { Int($0)! }
        let local = numbers[0] == 10 || numbers[0] == 127 ||
            (numbers[0] == 172 && (16...31).contains(numbers[1])) ||
            (numbers[0] == 192 && numbers[1] == 168)
        guard local else { throw FlowError.invalid("Pairing is limited to a private local network.") }
        let secret = try Data.decodeBase64URL(part(3), limit: 32)
        guard secret.count == 32 else { throw FlowError.invalid("Invalid pairing secret.") }
        return PairAddress(host: host, port: port, secret: secret)
    }
}

extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    static func decodeBase64URL(_ text: String, limit: Int) throws -> Data {
        guard text.utf8.count <= ((limit + 2) / 3) * 4,
              text.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw FlowError.invalid("Invalid encoded frame.")
        }
        let padded = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + String(repeating: "=", count: (4 - text.count % 4) % 4)
        guard let bytes = Data(base64Encoded: padded), bytes.count <= limit, bytes.base64URL == text else {
            throw FlowError.invalid("Invalid encoded frame.")
        }
        return bytes
    }
}

struct FlowKeys {
    let proof: SymmetricKey
    let transmit: SymmetricKey
    let receive: SymmetricKey
    let transcript: Data
}

/// Wire format v1 matches desktop/src/flow.js; this is always the joining client.
enum FlowProtocol {
    static let maximumFrame = 8 * 1024 * 1024
    static let maximumFile = 4 * 1024 * 1024
    static let maximumSequence: UInt64 = 9_007_199_254_740_991 // Node Number.MAX_SAFE_INTEGER
    static let spkiPrefix = Data([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x03, 0x21, 0x00])

    static func spki(_ key: Curve25519.KeyAgreement.PublicKey) -> Data { spkiPrefix + key.rawRepresentation }
    static func derive(privateKey: Curve25519.KeyAgreement.PrivateKey, serverSPKI: Data, secret: Data) throws -> FlowKeys {
        guard serverSPKI.count == 44, serverSPKI.prefix(12) == spkiPrefix, secret.count == 32 else { throw FlowError.invalid("Invalid peer public key.") }
        let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: serverSPKI.suffix(32))
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        let transcript = spki(privateKey.publicKey) + serverSPKI
        let material = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: secret, sharedInfo: transcript, outputByteCount: 96)
        let bytes = material.withUnsafeBytes { Data($0) }
        return FlowKeys(proof: SymmetricKey(data: bytes.prefix(32)), transmit: SymmetricKey(data: bytes.suffix(32)), receive: SymmetricKey(data: bytes.subdata(in: 32..<64)), transcript: transcript)
    }
    static func proof(_ keys: FlowKeys, role: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: keys.transcript + Data(role.utf8), using: keys.proof))
    }
    static func validateServerProof(_ proof: String, keys: FlowKeys) throws {
        let bytes = try Data.decodeBase64URL(proof, limit: 32)
        guard bytes.count == 32, HMAC<SHA256>.isValidAuthenticationCode(bytes, authenticating: keys.transcript + Data("server".utf8), using: keys.proof) else {
            throw FlowError.invalid("Pairing authentication failed. Create a new code on the desktop.")
        }
    }
    static func json(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else { throw FlowError.invalid("Invalid message.") }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    static func object(_ bytes: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw FlowError.invalid("Invalid message.") }
        return object
    }
    static func frame(_ object: [String: Any]) throws -> Data {
        let bytes = try json(object)
        guard !bytes.isEmpty, bytes.count <= maximumFrame else { throw FlowError.invalid("Transfer exceeds the frame limit.") }
        var count = UInt32(bytes.count).bigEndian
        return withUnsafeBytes(of: &count) { Data($0) } + bytes
    }
    static func seal(_ payload: [String: Any], sequence: UInt64, key: SymmetricKey, nonce: AES.GCM.Nonce = AES.GCM.Nonce()) throws -> [String: Any] {
        guard sequence > 0, sequence <= maximumSequence else { throw FlowError.invalid("Session counter exhausted; pair again.") }
        let plain = try json(payload)
        guard plain.count <= maximumFrame - 1000 else { throw FlowError.invalid("Transfer exceeds the payload limit.") }
        let box = try AES.GCM.seal(plain, using: key, nonce: nonce, authenticating: Data(String(sequence).utf8))
        return ["kind": "sealed", "seq": sequence, "iv": box.nonce.withUnsafeBytes { Data($0).base64URL }, "data": box.ciphertext.base64URL, "tag": box.tag.base64URL]
    }
    static func open(_ object: [String: Any], expectedSequence: UInt64, key: SymmetricKey) throws -> [String: Any] {
        guard object["kind"] as? String == "sealed", let raw = object["seq"] as? NSNumber,
              CFGetTypeID(raw) != CFBooleanGetTypeID(), raw.doubleValue.isFinite,
              raw.doubleValue == Double(expectedSequence), expectedSequence > 0, expectedSequence <= maximumSequence,
              let iv = object["iv"] as? String, let ciphertext = object["data"] as? String, let tag = object["tag"] as? String else {
            throw FlowError.invalid("Replay or invalid encrypted message.")
        }
        let nonceData = try Data.decodeBase64URL(iv, limit: 12), tagData = try Data.decodeBase64URL(tag, limit: 16)
        guard nonceData.count == 12, tagData.count == 16 else { throw FlowError.invalid("Invalid encrypted message.") }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonceData), ciphertext: Data.decodeBase64URL(ciphertext, limit: maximumFrame), tag: tagData)
        let plain = try AES.GCM.open(box, using: key, authenticating: Data(String(expectedSequence).utf8))
        return try self.object(plain)
    }
}

enum TransferContent {
    case tab(URL, String)
    case text(String)
    case file(String, Data)
}

struct IncomingTransfer: Identifiable {
    let id = UUID()
    let content: TransferContent
    let receivedAt = Date()
    var title: String {
        switch content {
        case .tab(_, let title): return title.isEmpty ? "Browser tab" : title
        case .text: return "Text from your desktop"
        case .file(let name, _): return name
        }
    }
    var detail: String {
        switch content {
        case .tab(let url, _): return url.absoluteString
        case .text(let text): return String(text.prefix(180))
        case .file(_, let bytes): return ByteCountFormatter.string(fromByteCount: Int64(bytes.count), countStyle: .file)
        }
    }
    var byteCount: Int {
        switch content {
        case .tab(let url, let title): return url.absoluteString.utf8.count + title.utf8.count
        case .text(let text): return text.utf8.count
        case .file(_, let data): return data.count
        }
    }
    static func parse(_ payload: [String: Any]) throws -> IncomingTransfer {
        guard let type = payload["type"] as? String, let data = payload["data"] as? [String: Any] else { throw FlowError.invalid("Unsupported transfer.") }
        switch type {
        case "flow-tab":
            guard let raw = data["url"] as? String, raw.utf16.count <= 4096,
                  let url = safeWebURL(raw) else { throw FlowError.invalid("The incoming tab URL is unsafe.") }
            return IncomingTransfer(content: .tab(url, String((data["title"] as? String ?? "Browser tab").prefix(160))))
        case "drop-text":
            guard let text = data["text"] as? String, text.utf16.count <= 100_000 else { throw FlowError.invalid("Text exceeds 100,000 characters.") }
            return IncomingTransfer(content: .text(text))
        case "drop-file":
            guard let name = data["name"] as? String, !name.isEmpty, name.utf8.count <= 1024,
                  let encoded = data["data"] as? String, encoded.utf8.count <= ((FlowProtocol.maximumFile + 2) / 3) * 4,
                  let bytes = Data(base64Encoded: encoded), bytes.count <= FlowProtocol.maximumFile,
                  bytes.base64EncodedString() == encoded else { throw FlowError.invalid("File exceeds 4 MiB or is invalid.") }
            return IncomingTransfer(content: .file(safeFileName(name), bytes))
        default: throw FlowError.invalid("Unsupported transfer type.")
        }
    }
}

func safeWebURL(_ raw: String) -> URL? {
    guard raw.utf16.count <= 4096, !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
          let url = URL(string: raw), let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
          let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
    return url
}

func safeFileName(_ raw: String) -> String {
    let leaf = raw.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? "Transfer.bin"
    let clean = String(String.UnicodeScalarView(leaf.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != ":" }.prefix(160)))
    return clean.isEmpty || clean == "." || clean == ".." ? "Transfer.bin" : clean
}
