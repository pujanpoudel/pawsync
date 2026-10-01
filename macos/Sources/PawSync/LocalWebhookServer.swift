import Foundation
import Network
import CryptoKit

final class LocalWebhookServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.pawsync.webhook", qos: .utility)
    private var connections: [UUID: NWConnection] = [:]
    private var second = Date.distantPast
    private var count = 0
    var onStatus: ((String) -> Void)?
    var onError: ((String) -> Void)?

    func start(token: String) throws {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 9876)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.onError?("Could not listen on 127.0.0.1:9876. Another process may be using the port.")
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection, token: token) }
        listener.start(queue: queue)
    }
    func stop() {
        let listener = self.listener; self.listener = nil
        listener?.cancel()
        queue.async { [weak self] in
            self?.connections.values.forEach { $0.cancel() }; self?.connections.removeAll()
        }
    }
    private func accept(_ connection: NWConnection, token: String) {
        if Date().timeIntervalSince(second) >= 1 { second = Date(); count = 0 }
        count += 1
        guard count <= 10, connections.count < 16 else { connection.start(queue: queue); respond(connection, code: 429); return }
        let id = UUID(); connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { self?.connections.removeValue(forKey: id) }
            if case .failed = state { self?.connections.removeValue(forKey: id) }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
        read(connection, data: Data(), token: token)
    }
    private func read(_ connection: NWConnection, data: Data, token: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] chunk, _, complete, error in
            guard let self else { connection.cancel(); return }
            var accumulated = data; if let chunk { accumulated.append(chunk) }
            guard accumulated.count <= 12_288 else { self.respond(connection, code: 413); return }
            if let separator = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                guard separator.lowerBound <= 8192, let headers = String(data: accumulated[..<separator.lowerBound], encoding: .utf8) else { self.respond(connection, code: 400); return }
                let lines = headers.components(separatedBy: "\r\n")
                guard lines.first == "POST /v1/status HTTP/1.1" else { self.respond(connection, code: 404); return }
                var values: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { self.respond(connection, code: 400); return }
                    let key = line[..<colon].lowercased()
                    guard values[key] == nil else { self.respond(connection, code: 400); return }
                    values[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
                guard values["transfer-encoding"] == nil, let length = Int(values["content-length"] ?? ""), (1...4096).contains(length), values["content-type"]?.hasPrefix("application/json") == true else { self.respond(connection, code: 400); return }
                let end = separator.upperBound + length
                if accumulated.count >= end {
                    guard Self.constantEqual(values["authorization"] ?? "", "Bearer \(token)") else { self.respond(connection, code: 401); return }
                    guard accumulated.count == end, let payload = try? JSONSerialization.jsonObject(with: accumulated[separator.upperBound..<end]) as? [String: Any], let status = payload["status"] as? String, ["build_success", "build_failed"].contains(status) else { self.respond(connection, code: 400); return }
                    self.onStatus?(status); self.respond(connection, code: 200); return
                }
            }
            guard !complete, error == nil else { self.respond(connection, code: 400); return }
            self.read(connection, data: accumulated, token: token)
        }
    }
    private func respond(_ connection: NWConnection, code: Int) {
        let reasons = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 413: "Payload Too Large", 429: "Too Many Requests"]
        let body = code == 200 ? "{\"ok\":true}" : "{\"ok\":false}"
        let response = "HTTP/1.1 \(code) \(reasons[code] ?? "Error")\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
    private static func constantEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(SHA256.hash(data: Data(lhs.utf8))), b = Array(SHA256.hash(data: Data(rhs.utf8)))
        var difference: UInt8 = 0
        for index in a.indices { difference |= a[index] ^ b[index] }
        return difference == 0
    }
}
