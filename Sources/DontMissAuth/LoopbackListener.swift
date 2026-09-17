import Foundation
import Network

@MainActor
final class LoopbackListener {
    private let expectedState: String
    private var listener: NWListener?
    private var ready: CheckedContinuation<URL, Error>?
    private var callback: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?
    private var timeout: Task<Void, Never>?
    private var connections: [UUID: NWConnection] = [:]
    private var connectionTimeouts: [UUID: Task<Void, Never>] = [:]
    private var redirect: URL?

    init(state: String) { expectedState = state }

    func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.stateChanged(state) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(180)) }
            catch { return }
            self?.finish(.failure(OAuthError.timedOut))
        }
        return try await withCheckedThrowingContinuation { continuation in
            ready = continuation
            listener.start(queue: .main)
        }
    }

    func code() async throws -> String {
        if let result { return try result.get() }
        return try await withCheckedThrowingContinuation { callback = $0 }
    }

    func cancel() { finish(.failure(OAuthError.cancelled)) }

    private func stateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener?.port,
                  let url = URL(string: "http://127.0.0.1:\(port.rawValue)/oauth/callback") else {
                finish(.failure(OAuthError.callback))
                return
            }
            redirect = url
            ready?.resume(returning: url)
            ready = nil
        case .failed(let error):
            finish(.failure(OAuthError.listener(error.localizedDescription)))
        default: break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard result == nil, connections.count < 8 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: .main)
        connectionTimeouts[id] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
            self?.close(id)
        }
        receive(id, buffer: Data())
    }

    private func receive(_ id: UUID, buffer: Data) {
        guard let connection = connections[id] else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { return }
                var bytes = buffer
                if let data { bytes.append(data) }
                guard bytes.count <= 8192, error == nil else { self.close(id); return }
                if let text = String(data: bytes, encoding: .utf8), text.contains("\r\n\r\n") {
                    self.handle(text, id: id)
                } else if complete {
                    self.close(id)
                } else {
                    self.receive(id, buffer: bytes)
                }
            }
        }
    }

    private func handle(_ request: String, id: UUID) {
        guard result == nil, let redirect else { close(id); return }
        let lines = request.components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ")
        let host = lines.dropFirst().first { $0.lowercased().hasPrefix("host:") }?
            .dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard first.count == 3, first[0] == "GET",
              host == "127.0.0.1:\(redirect.port ?? 0)" else {
            respond(id, status: "400 Bad Request", message: "Invalid OAuth request.")
            return
        }
        do {
            let code = try OAuthSupport.callback(target: String(first[1]), state: expectedState)
            respond(id, status: "200 OK", message: "Authorization received. Return to Don't Miss to finish connecting.")
            finish(.success(code), preserving: id)
        } catch OAuthError.denied {
            respond(id, status: "200 OK", message: "Access was not granted. Return to Don't Miss to try again.")
            finish(.failure(OAuthError.denied), preserving: id)
        } catch {
            // Unsolicited requests must not cancel a legitimate sign-in in progress.
            respond(id, status: "400 Bad Request", message: "Invalid OAuth callback. Return to Don't Miss.")
        }
    }

    private func respond(_ id: UUID, status: String, message: String) {
        let body = Data(message.utf8)
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connections[id]?.send(content: Data(headers.utf8) + body, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.close(id) }
        })
    }

    private func close(_ id: UUID) {
        connections.removeValue(forKey: id)?.cancel()
        connectionTimeouts.removeValue(forKey: id)?.cancel()
    }

    private func finish(_ result: Result<String, Error>, preserving id: UUID? = nil) {
        guard self.result == nil else { return }
        self.result = result
        timeout?.cancel()
        timeout = nil
        listener?.cancel()
        listener = nil
        if let ready {
            self.ready = nil
            switch result {
            case .failure(let error): ready.resume(throwing: error)
            case .success: ready.resume(throwing: OAuthError.callback)
            }
        }
        callback?.resume(with: result)
        callback = nil
        for connectionID in Array(connections.keys) where connectionID != id { close(connectionID) }
    }
}
