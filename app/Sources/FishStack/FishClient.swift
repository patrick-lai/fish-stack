import Foundation

struct FishError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

struct RoleHealth: Decodable, Equatable {
    let model: String
    let revision: String
    let state: String
    let loaded: Bool
}

/// What the server has answered since it started. Absent on servers that predate the counters.
struct Activity: Decodable, Equatable {
    let decisions: Int
    let embeddings: Int
    let leases: Int
}

struct Health: Decodable, Equatable {
    let status: String
    let roles: [String: RoleHealth]
    let activity: Activity?
}

struct ModelRecord: Decodable, Equatable, Identifiable {
    let id: String
    let repo: String
    let revision: String
    let role: String
    let state: String
    let bytesDone: Int64
    let bytesTotal: Int64?
    let active: Bool
    let error: String?

    var isDownloading: Bool {
        ["starting", "downloading", "converting"].contains(state)
    }

    var progress: Double? {
        guard let total = bytesTotal, total > 0 else { return nil }
        return min(Double(bytesDone) / Double(total), 1)
    }
}

private struct ModelList: Decodable {
    let data: [ModelRecord]
}

private struct Detail: Decodable {
    let detail: String
}

/// Talks to fishd on loopback. The bearer key is read from the state directory on each call,
/// so a key written after the server starts is picked up without restarting the app.
struct FishClient: Sendable {
    let port: Int
    let keyFile: URL

    func health() async throws -> Health {
        try await send("GET", "/health", authorized: false)
    }

    func isServing() async -> Bool {
        (try? await health()) != nil
    }

    func models() async throws -> [ModelRecord] {
        let list: ModelList = try await send("GET", "/v1/models")
        return list.data
    }

    func startDownload(source: String, role: String) async throws {
        let _: ModelRecord = try await send("POST", "/v1/models", body: ["source": source, "role": role])
    }

    func cancel(_ id: String) async throws {
        let _: Detail = try await send("POST", "/v1/models/\(id)/cancel")
    }

    func delete(_ id: String) async throws {
        let _: Detail = try await send("DELETE", "/v1/models/\(id)")
    }

    private func send<Response: Decodable>(_ method: String, _ path: String, body: [String: String]? = nil, authorized: Bool = true) async throws -> Response {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else {
            throw FishError("The model server address is invalid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 5
        if authorized {
            request.setValue("Bearer " + (try readKey()), forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSONDecoder().decode(Detail.self, from: data))?.detail
            throw FishError(detail ?? "Fish Stack answered with HTTP \(status).")
        }
        return try Self.decode(Response.self, from: data)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }

    private func readKey() throws -> String {
        guard let text = try? String(contentsOf: keyFile, encoding: .utf8) else {
            throw FishError("Fish Stack has not created its key yet. It may still be starting.")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
