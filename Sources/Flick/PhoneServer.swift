import Foundation
import Network

final class PhoneServer: @unchecked Sendable {
    static let fallbackFileName = "Video from phone.mov"

    var onLink: ((URL) -> Void)?
    var onUploadStarted: ((PhoneUpload) -> Void)?
    var onUploadEnded: ((PhoneUpload) -> Void)?
    let token: String
    private let destination: URL
    private let listener: NWListener
    private let queue = DispatchQueue(label: "PhoneServer")
    private var exchanges: [ObjectIdentifier: PhoneExchange] = [:]

    init(destination: URL, port: NWEndpoint.Port = .any, token: String = PhoneServer.makeToken()) throws {
        self.destination = destination
        self.token = token
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters, on: port)
    }

    static func makeToken() -> String {
        (0..<16).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
    }

    func start(onReady: @escaping (UInt16?) -> Void) {
        listener.stateUpdateHandler = { [listener] state in
            switch state {
            case .ready: DispatchQueue.main.async { onReady(listener.port?.rawValue) }
            case .failed: DispatchQueue.main.async { onReady(nil) }
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
    }

    func stopListening() {
        listener.cancel()
    }

    func pageURL(host: String, port: UInt16) -> URL? {
        URL(string: "http://\(host):\(port)/\(token)/")
    }

    static func uniqueFile(named name: String, in folder: URL) -> URL {
        let cleaned = name.replacingOccurrences(of: ":", with: "-").split(separator: "/").last.map(String.init) ?? ""
        let base = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
        let file = folder.appending(component: base.isEmpty ? fallbackFileName : base)
        let stem = file.deletingPathExtension().lastPathComponent
        let fileExtension = file.pathExtension
        var candidate = file
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = "\(stem) \(number)"
            candidate = folder.appending(component: fileExtension.isEmpty ? numbered : "\(numbered).\(fileExtension)")
            number += 1
        }
        return candidate
    }

    private func accept(_ connection: NWConnection) {
        let exchange = PhoneExchange(connection: connection, routes: self)
        let key = ObjectIdentifier(exchange)
        exchanges[key] = exchange
        exchange.onClose = { [weak self] in self?.queue.async { self?.exchanges[key] = nil } }
        exchange.start()
    }

    fileprivate func respond(to head: PhoneRequestHead) -> PhoneRoute {
        guard head.pathComponents.first == token else { return .respond(.notFound) }
        switch (head.method, Array(head.pathComponents.dropFirst())) {
        case ("GET", []):
            return .respond(.page)
        case ("POST", ["link"]):
            return .readLink
        case ("PUT", ["upload"]):
            guard let size = head.contentLength, size > 0 else { return .respond(.badRequest) }
            return .receiveFile(named: head.query["name"] ?? Self.fallbackFileName, size: size)
        default:
            return .respond(.notFound)
        }
    }

    fileprivate func receivedLink(_ text: String) -> Bool {
        guard let url = URL(webVideoString: text) else { return false }
        DispatchQueue.main.async { [weak self] in self?.onLink?(url) }
        return true
    }

    fileprivate func startUpload(named name: String, size: Int64) -> PhoneUpload? {
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let upload = try? PhoneUpload(file: Self.uniqueFile(named: name, in: destination), size: size) else { return nil }
        DispatchQueue.main.async { [weak self] in self?.onUploadStarted?(upload) }
        return upload
    }

    fileprivate func endUpload(_ upload: PhoneUpload) {
        DispatchQueue.main.async { [weak self] in self?.onUploadEnded?(upload) }
    }
}

struct PhoneRequestHead: Equatable {
    static let maximumSize = 16 * 1024

    let method: String
    let pathComponents: [String]
    let query: [String: String]
    let headers: [String: String]

    init?(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count == 3, let target = URLComponents(string: String(requestLine[1])) else { return nil }
        method = String(requestLine[0])
        pathComponents = target.path.split(separator: "/").map(String.init)
        query = Dictionary((target.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        headers = Dictionary(lines.dropFirst().compactMap(Self.header), uniquingKeysWith: { first, _ in first })
    }

    var contentLength: Int64? {
        headers["content-length"].flatMap { Int64($0) }
    }

    var expectsContinue: Bool {
        headers["expect"]?.lowercased() == "100-continue"
    }

    private static func header(_ line: String) -> (String, String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return (name, value)
    }
}

private enum PhoneRoute {
    case respond(PhoneResponse)
    case readLink
    case receiveFile(named: String, size: Int64)
}

private enum PhoneResponse {
    case page
    case ok
    case badRequest
    case notFound
    case serverError

    var data: Data {
        let (status, type, body): (String, String, String) = switch self {
        case .page: ("200 OK", "text/html; charset=utf-8", PhonePage.html)
        case .ok: ("200 OK", "text/plain; charset=utf-8", "ok")
        case .badRequest: ("400 Bad Request", "text/plain; charset=utf-8", "bad request")
        case .notFound: ("404 Not Found", "text/plain; charset=utf-8", "not found")
        case .serverError: ("500 Internal Server Error", "text/plain; charset=utf-8", "could not save the video")
        }
        let bodyData = Data(body.utf8)
        let head = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(type)",
            "Content-Length: \(bodyData.count)",
            "Cache-Control: no-store",
            "Connection: close",
        ].joined(separator: "\r\n") + "\r\n\r\n"
        return Data(head.utf8) + bodyData
    }
}

private final class PhoneExchange {
    static let headEnd = Data("\r\n\r\n".utf8)
    static let maximumLinkSize = 8 * 1024
    static let chunkSize = 1 << 20

    var onClose: (() -> Void)?
    private let connection: NWConnection
    private let routes: PhoneServer
    private let queue = DispatchQueue(label: "PhoneExchange")
    private var buffered = Data()
    private var upload: PhoneUpload?

    init(connection: NWConnection, routes: PhoneServer) {
        self.connection = connection
        self.routes = routes
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        connection.start(queue: queue)
        readHead()
    }

    private func readHead() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: PhoneRequestHead.maximumSize) { [self] data, _, isComplete, error in
            if let data { buffered.append(data) }
            if let end = buffered.range(of: Self.headEnd) {
                let head = buffered[..<end.lowerBound]
                buffered = Data(buffered[end.upperBound...])
                return handle(PhoneRequestHead(Data(head)))
            }
            guard error == nil, !isComplete, buffered.count < PhoneRequestHead.maximumSize else { return connection.cancel() }
            readHead()
        }
    }

    private func handle(_ head: PhoneRequestHead?) {
        guard let head else { return send(.badRequest) }
        if head.expectsContinue { connection.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .idempotent) }
        switch routes.respond(to: head) {
        case let .respond(response): send(response)
        case .readLink: readLink(expecting: Int(head.contentLength ?? 0))
        case let .receiveFile(name, size): receiveFile(named: name, size: size)
        }
    }

    private func readLink(expecting size: Int) {
        guard size > 0, size <= Self.maximumLinkSize else { return send(.badRequest) }
        guard buffered.count < size else {
            let text = String(decoding: buffered.prefix(size), as: UTF8.self)
            return send(routes.receivedLink(text) ? .ok : .badRequest)
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: size - buffered.count) { [self] data, _, isComplete, error in
            if let data { buffered.append(data) }
            guard error == nil, !(isComplete && buffered.count < size) else { return connection.cancel() }
            readLink(expecting: size)
        }
    }

    private func receiveFile(named name: String, size: Int64) {
        guard let upload = routes.startUpload(named: name, size: size) else { return send(.serverError) }
        self.upload = upload
        let early = buffered.prefix(Int(min(Int64(buffered.count), size)))
        buffered = Data()
        store(early, in: upload)
    }

    private func store(_ data: Data, in upload: PhoneUpload) {
        guard (try? upload.append(data)) != nil else { return abandon(upload, answering: .serverError) }
        let remaining = upload.size - upload.receivedBytes
        guard remaining > 0 else {
            upload.finish()
            end(upload)
            return send(.ok)
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: Int(min(remaining, Int64(Self.chunkSize)))) { [self] data, _, _, error in
            guard error == nil, let data, !data.isEmpty else { return abandon(upload, answering: nil) }
            store(data, in: upload)
        }
    }

    private func abandon(_ upload: PhoneUpload, answering response: PhoneResponse?) {
        upload.fail()
        end(upload)
        guard let response else { return connection.cancel() }
        send(response)
    }

    private func end(_ upload: PhoneUpload) {
        self.upload = nil
        routes.endUpload(upload)
    }

    private func send(_ response: PhoneResponse) {
        connection.send(content: response.data, completion: .contentProcessed { [connection] _ in connection.cancel() })
    }

    private func close() {
        if let upload { abandon(upload, answering: nil) }
        onClose?()
        onClose = nil
    }
}
