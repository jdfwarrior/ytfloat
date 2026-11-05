import Foundation
import Network

/// A fixed-route HTTP/1.1 asset server. No filesystem paths, proxying, or command endpoints.
public final class HTTPServer {
    public struct Asset {
        public let data: Data
        public let contentType: String
        public init(data: Data, contentType: String) { self.data = data; self.contentType = contentType }
    }
    private let queue = DispatchQueue(label: "co.ytfloat.http")
    private let listener: NWListener
    private let token = UUID().uuidString.lowercased()
    private let assets: [String: Asset]
    private var connections: [UUID: NWConnection] = [:]
    private var completion: ((Result<URL, Error>) -> Void)?
    private var host = ""

    public init(assets: [String: Asset]) throws {
        self.assets = assets
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    public func start(completion: @escaping (Result<URL, Error>) -> Void) {
        self.completion = completion
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard let port = self.listener.port else { return }
                self.host = "127.0.0.1:\(port.rawValue)"
                self.finish(.success(URL(string: "http://\(self.host)/\(self.token)/index.html")!))
            case .failed(let error): self.finish(.failure(error))
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.connections.count < 16 else { connection.cancel(); return }
            let id = UUID()
            self.connections[id] = connection
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .cancelled, .failed: self?.connections.removeValue(forKey: id)
                default: break
                }
            }
            connection.start(queue: self.queue)
            self.receive(connection, buffer: Data())
            self.queue.asyncAfter(deadline: .now() + 5) { [weak connection] in connection?.cancel() }
        }
        listener.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.finish(.failure(IPCError.system("The local player server did not start in time.")))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        let callback = completion
        completion = nil
        DispatchQueue.main.async { callback?(result) }
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192 - buffer.count) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self.respond(connection, header: String(decoding: buffer[..<end.lowerBound], as: UTF8.self))
            } else if buffer.count >= 8192 || complete || error != nil {
                connection.cancel()
            } else { self.receive(connection, buffer: buffer) }
        }
    }

    private func respond(_ connection: NWConnection, header: String) {
        let lines = header.components(separatedBy: "\r\n")
        let request = lines.first?.split(separator: " ").map(String.init) ?? []
        var status = "404 Not Found"
        var asset = Asset(data: Data("Not found".utf8), contentType: "text/plain; charset=utf-8")
        let hosts = lines.dropFirst().compactMap { line -> String? in
            guard let colon = line.firstIndex(of: ":"), line[..<colon].lowercased() == "host" else { return nil }
            return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        if request.count == 3, request[2] == "HTTP/1.1", hosts == [host] {
            if request[0] != "GET" { status = "405 Method Not Allowed" }
            else if request[1].hasPrefix("/\(token)/"),
                    let found = assets[String(request[1].dropFirst(token.count + 2))] {
                status = "200 OK"; asset = found
            }
        } else { status = "400 Bad Request" }
        // Cross-origin embeds need the actual HTTP origin as their Referer, never file:// or null.
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: \(asset.contentType)\r\nContent-Length: \(asset.data.count)\r\nConnection: close\r\nCache-Control: no-store\r\nReferrer-Policy: strict-origin-when-cross-origin\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\n\r\n"
        var response = Data(headers.utf8)
        response.append(asset.data)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    public func stop() {
        queue.sync {
            completion = nil
            listener.stateUpdateHandler = nil
            listener.newConnectionHandler = nil
            listener.cancel()
            for connection in connections.values { connection.stateUpdateHandler = nil; connection.cancel() }
            connections.removeAll()
        }
    }
}
