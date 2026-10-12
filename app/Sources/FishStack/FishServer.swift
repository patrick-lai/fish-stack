import Foundation
import Observation

struct ServerConfig {
    let port: Int
    let stateDir: URL
    let runtimeDir: URL?

    static func fromEnvironment() -> ServerConfig {
        let env = ProcessInfo.processInfo.environment
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FishStack", isDirectory: true)
        let port: Int
        if let raw = env["FISH_STACK_PORT"] {
            guard let parsed = Int(raw), (1024...65535).contains(parsed) else {
                preconditionFailure("FISH_STACK_PORT must be a port number between 1024 and 65535")
            }
            port = parsed
        } else {
            port = 8089
        }
        return ServerConfig(
            port: port,
            stateDir: env["FISH_STACK_STATE"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? support,
            runtimeDir: env["FISH_STACK_RUNTIME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? Bundle.main.resourceURL?.appendingPathComponent("runtime", isDirectory: true)
        )
    }
}

/// Owns the fishd process: installs the Python runtime, starts the server when none is running,
/// and keeps the served models and downloads current for the menu.
@MainActor
@Observable
final class FishServer {
    private(set) var health: Health?
    private(set) var models: [ModelRecord] = []
    private(set) var phase = "Starting"
    /// The latest failure to show in the menu. Cleared when an action succeeds.
    private(set) var notice: String?

    private let config: ServerConfig
    private let client: FishClient
    private var process: Process?
    private var supervisor: Task<Void, Never>?

    init(config: ServerConfig = .fromEnvironment()) {
        self.config = config
        client = FishClient(port: config.port, keyFile: config.stateDir.appendingPathComponent("api-key"))
    }

    var port: Int { config.port }
    var stateURL: URL { config.stateDir }
    var logsURL: URL { config.stateDir.appendingPathComponent("logs", isDirectory: true) }

    func start() {
        guard supervisor == nil else { return }
        supervisor = Task { await supervise() }
    }

    func download(source: String, role: String) async {
        await perform { try await client.startDownload(source: source, role: role) }
    }

    func cancel(_ model: ModelRecord) async {
        await perform { try await client.cancel(model.id) }
    }

    func delete(_ model: ModelRecord) async {
        await perform { try await client.delete(model.id) }
    }

    private func perform(_ action: () async throws -> Void) async {
        do {
            try await action()
            notice = nil
            await refresh()
        } catch {
            notice = error.localizedDescription
        }
    }

    private func supervise() async {
        if await client.isServing() {
            phase = "Running"
        } else {
            do {
                try await prepareRuntime()
                try launch()
                phase = "Starting"
            } catch {
                notice = error.localizedDescription
                phase = "Stopped"
                return
            }
        }
        while !Task.isCancelled {
            await refresh()
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
        }
    }

    private func refresh() async {
        do {
            health = try await client.health()
            models = try await client.models()
            phase = "Running"
        } catch {
            health = nil
            if process?.isRunning == true {
                phase = "Starting"
            } else {
                phase = "Stopped"
                notice = notice ?? "The model server is not running. See the fishd log in the state folder."
            }
        }
    }

    private var venvURL: URL {
        config.stateDir.appendingPathComponent("venv", isDirectory: true)
    }

    private func prepareRuntime() async throws {
        guard let runtime = config.runtimeDir, FileManager.default.fileExists(atPath: runtime.path) else {
            throw FishError("The model runtime is missing from this app. Rebuild it with make app.")
        }
        guard let uv = Self.locateUV() else {
            throw FishError("Install uv to set up the model runtime: brew install uv")
        }
        phase = "Installing the model runtime"
        try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
        try await Self.run(
            uv,
            ["sync", "--project", runtime.path, "--frozen", "--python", "3.12"],
            environment: ["UV_PROJECT_ENVIRONMENT": venvURL.path],
            log: logsURL.appendingPathComponent("uv.log")
        )
    }

    private func launch() throws {
        let process = Process()
        process.executableURL = venvURL.appendingPathComponent("bin/python")
        process.arguments = ["-m", "fishd", "serve", "--port", String(config.port), "--state-dir", config.stateDir.path]
        let log = try Self.logHandle(logsURL.appendingPathComponent("fishd.log"))
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.phase = "Stopped" }
        }
        try process.run()
        self.process = process
    }

    private static func locateUV() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = ["/opt/homebrew/bin/uv", "/usr/local/bin/uv", home.appendingPathComponent(".local/bin/uv").path]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    private static func run(_ tool: URL, _ arguments: [String], environment: [String: String], log: URL) async throws {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let output = try logHandle(log)
        process.standardOutput = output
        process.standardError = output
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in continuation.resume(returning: finished.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else {
            throw FishError("Installing the model runtime failed. See \(log.lastPathComponent) in the logs folder.")
        }
    }

    private static func logHandle(_ url: URL) throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        _ = try handle.seekToEnd()
        return handle
    }
}
