import Foundation
import Combine
import Network
import CryptoKit

/// Network callbacks and UI operations all run on the main queue.
final class FlowClient: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published private(set) var status = "No paired device"
    @Published private(set) var incoming: [IncomingTransfer] = []
    @Published private(set) var sending = false
    @Published var errorMessage: String?

    private var connection: NWConnection?
    private var privateKey: Curve25519.KeyAgreement.PrivateKey?
    private var secret: Data?
    private var keys: FlowKeys?
    private var buffer = Data()
    private var sendSequence: UInt64 = 0
    private var receiveSequence: UInt64 = 0
    private var handshakeTimeout: DispatchWorkItem?
    private var frameTimeout: DispatchWorkItem?
    private var sendTimeout: DispatchWorkItem?
    private var generation = UUID()

    func join(_ code: String) {
        disconnect()
        do {
            let address = try PairAddress.parse(code)
            guard let port = NWEndpoint.Port(rawValue: address.port) else { throw FlowError.invalid("Invalid port.") }
            secret = address.secret
            privateKey = Curve25519.KeyAgreement.PrivateKey()
            status = "Connecting to \(address.host)…"
            connecting = true
            let socket = NWConnection(host: NWEndpoint.Host(address.host), port: port, using: .tcp)
            connection = socket
            let session = generation
            socket.stateUpdateHandler = { [weak self] state in
                guard let self = self, self.generation == session else { return }
                switch state {
                case .ready:
                    do {
                        guard let key = self.privateKey else { return }
                        try self.write(["kind": "hello", "pub": FlowProtocol.spki(key.publicKey).base64URL])
                        self.receive(session: session)
                    } catch { self.fail(error) }
                case .failed(let error): self.fail(error)
                case .waiting: self.status = "Waiting for local network access…"
                case .cancelled: if self.connected || self.connecting { self.disconnect() }
                default: break
                }
            }
            let timer = DispatchWorkItem { [weak self] in
                guard let self = self, self.generation == session, !self.connected else { return }
                self.fail(FlowError.invalid("Pairing timed out. Check Wi-Fi, Local Network permission and Windows Firewall; create a new desktop code."))
            }
            handshakeTimeout = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timer)
            socket.start(queue: .main)
        } catch { fail(error) }
    }

    func disconnect() {
        generation = UUID()
        handshakeTimeout?.cancel(); handshakeTimeout = nil
        frameTimeout?.cancel(); frameTimeout = nil
        sendTimeout?.cancel(); sendTimeout = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel(); connection = nil
        privateKey = nil; secret = nil; keys = nil
        buffer.removeAll(keepingCapacity: false)
        connected = false; connecting = false; sending = false
        sendSequence = 0; receiveSequence = 0
        status = "No paired device"
        // Pending transfers belong to this session and are never auto-accepted.
        incoming.removeAll()
    }

    private func fail(_ error: Error) {
        disconnect()
        errorMessage = error.localizedDescription
    }

    private func write(_ object: [String: Any], completion: (() -> Void)? = nil) throws {
        guard let socket = connection else { throw FlowError.invalid("Pair a desktop first.") }
        let data = try FlowProtocol.frame(object), session = generation
        socket.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self = self, self.generation == session else { return }
            if let error = error { self.fail(error) } else { completion?() }
        })
    }

    private func receive(session: UUID) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self = self, self.generation == session else { return }
            if let error = error { self.fail(error); return }
            do {
                if let data = data, !data.isEmpty {
                    guard self.buffer.count + data.count <= FlowProtocol.maximumFrame + 4 + 65_536 else { throw FlowError.invalid("Incoming buffer limit exceeded.") }
                    self.buffer.append(data)
                    while self.buffer.count >= 4 {
                        let size = self.buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                        let limit = self.connected ? FlowProtocol.maximumFrame : 4096
                        guard size > 0, size <= limit else { throw FlowError.invalid("Invalid frame length.") }
                        guard self.buffer.count >= Int(size) + 4 else { break }
                        let bytes = self.buffer.subdata(in: 4..<(Int(size) + 4))
                        self.buffer.removeSubrange(0..<(Int(size) + 4))
                        self.frameTimeout?.cancel(); self.frameTimeout = nil
                        try self.handle(FlowProtocol.object(bytes))
                    }
                    if !self.buffer.isEmpty && self.frameTimeout == nil {
                        let timer = DispatchWorkItem { [weak self] in
                            guard let self = self, self.generation == session else { return }
                            self.fail(FlowError.invalid("The incoming frame timed out."))
                        }
                        self.frameTimeout = timer
                        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timer)
                    }
                }
                if complete {
                    self.disconnect()
                    self.status = "Desktop disconnected. Pair again to reconnect."
                } else { self.receive(session: session) }
            } catch { self.fail(error) }
        }
    }

    private func handle(_ object: [String: Any]) throws {
        if !connected {
            guard object["kind"] as? String == "challenge", let pub = object["pub"] as? String, let proof = object["proof"] as? String,
                  let secret = secret, let privateKey = privateKey else { throw FlowError.invalid("Unexpected pairing response.") }
            let keys = try FlowProtocol.derive(privateKey: privateKey, serverSPKI: Data.decodeBase64URL(pub, limit: 44), secret: secret)
            try FlowProtocol.validateServerProof(proof, keys: keys)
            try write(["kind": "proof", "proof": FlowProtocol.proof(keys, role: "client").base64URL])
            self.keys = keys; self.privateKey = nil; self.secret = nil
            connected = true; connecting = false; status = "Paired · encrypted local connection"
            handshakeTimeout?.cancel(); handshakeTimeout = nil
            return
        }
        guard let keys = keys, receiveSequence < FlowProtocol.maximumSequence else { throw FlowError.invalid("Pair again to start a new session.") }
        let payload = try FlowProtocol.open(object, expectedSequence: receiveSequence + 1, key: keys.receive)
        let transfer = try IncomingTransfer.parse(payload)
        guard incoming.count < 20, incoming.reduce(0, { $0 + $1.byteCount }) + transfer.byteCount <= 16 * 1024 * 1024 else {
            throw FlowError.invalid("The incoming queue is full. Handle pending transfers before reconnecting.")
        }
        receiveSequence += 1
        incoming.append(transfer)
    }

    func dismiss(_ transfer: IncomingTransfer) { incoming.removeAll { $0.id == transfer.id } }

    func sendTab(url: URL, title: String) {
        send(type: "flow-tab", data: ["url": url.absoluteString, "title": String(title.prefix(160)), "scrollY": 0])
    }
    func sendText(_ text: String) { send(type: "drop-text", data: ["text": text]) }
    func sendFile(name: String, bytes: Data) {
        guard bytes.count <= FlowProtocol.maximumFile else { errorMessage = "Files must be 4 MiB or smaller."; return }
        send(type: "drop-file", data: ["name": safeFileName(name), "data": bytes.base64EncodedString()])
    }
    private func send(type: String, data: [String: Any]) {
        do {
            guard connected, let keys = keys else { throw FlowError.invalid("Pair your desktop first.") }
            guard !sending else { throw FlowError.invalid("Wait for the current transfer to finish sending.") }
            guard sendSequence < FlowProtocol.maximumSequence else { throw FlowError.invalid("Pair again to start a new session.") }
            let payload: [String: Any] = ["type": type, "data": data]
            _ = try IncomingTransfer.parse(payload)
            let nextSequence = sendSequence + 1
            let sealed = try FlowProtocol.seal(payload, sequence: nextSequence, key: keys.transmit)
            // Validate frame size before committing the sequence counter.
            _ = try FlowProtocol.frame(sealed)
            sending = true
            let session = generation
            let timer = DispatchWorkItem { [weak self] in
                guard let self = self, self.generation == session, self.sending else { return }
                self.fail(FlowError.invalid("Sending timed out. Pair again before retrying."))
            }
            sendTimeout = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timer)
            try write(sealed) { [weak self] in
                self?.sendTimeout?.cancel(); self?.sendTimeout = nil
                self?.sending = false
                self?.status = "Sent · waiting for desktop approval"
            }
            sendSequence = nextSequence
        } catch { errorMessage = error.localizedDescription; sending = false }
    }
}
