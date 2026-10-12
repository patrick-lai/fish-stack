import Darwin
import Foundation
import Observation

/// Another app's tab in the shared tray. While it runs, the app writes `tray/<id>.json` under the FishStack home.
/// `url` is a loopback http page the tray shows in its popover; `order` sorts tabs, lowest first.
struct TrayGuest: Decodable, Equatable, Identifiable {
    let id: String
    let title: String
    let order: Int
    let url: String
    let pid: Int32

    static let reservedID = "fishstack"

    /// A guest is shown only when its id is well formed, its page is loopback http, and its process is alive.
    static func isUsable(_ guest: TrayGuest) -> Bool {
        guard guest.id != reservedID, guest.id.range(of: "^[a-z0-9-]{1,40}$", options: .regularExpression) != nil else {
            return false
        }
        guard let url = URL(string: guest.url), url.scheme == "http", ["127.0.0.1", "localhost"].contains(url.host ?? "") else {
            return false
        }
        guard guest.pid > 0 else { return false }
        return kill(guest.pid, 0) == 0 || errno == EPERM
    }
}

/// Watches the tray folder and keeps the list of live guest tabs current.
@MainActor
@Observable
final class TrayRegistry {
    private(set) var guests: [TrayGuest] = []
    private let directory: URL
    private var timer: Timer?

    init(home: URL = TrayRegistry.defaultHome()) {
        directory = home.appendingPathComponent("tray", isDirectory: true)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// The same home fishd uses: FISH_STACK_HOME when set, otherwise ~/.fishStack.
    nonisolated static func defaultHome() -> URL {
        if let override = ProcessInfo.processInfo.environment["FISH_STACK_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".fishStack", isDirectory: true)
    }

    /// Announces that Fish Stack owns the shared tray. Guests keep their own tray unless this file names a live process.
    func publishOwner() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let record = try? JSONSerialization.data(withJSONObject: ["pid": Int(getpid())])
        try? record?.write(to: ownerFile, options: .atomic)
    }

    func withdrawOwner() {
        try? FileManager.default.removeItem(at: ownerFile)
    }

    private var ownerFile: URL {
        directory.appendingPathComponent("owner.json")
    }

    func refresh() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        let found = files
            .filter { $0.pathExtension == "json" }
            .compactMap { file -> TrayGuest? in
                guard let data = try? Data(contentsOf: file), let guest = try? decoder.decode(TrayGuest.self, from: data) else {
                    return nil
                }
                return TrayGuest.isUsable(guest) ? guest : nil
            }
            .sorted { ($0.order, $0.id) < ($1.order, $1.id) }
        if found != guests {
            guests = found
        }
    }
}
