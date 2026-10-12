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

/// Keeps the list of live guest tabs current without polling. It wakes only when a file in the tray folder
/// changes, or when a guest's process exits, so an idle menu bar costs nothing.
@MainActor
@Observable
final class TrayRegistry {
    private(set) var guests: [TrayGuest] = []
    /// True while the popover is open. Guest pages are loaded only then, so a closed popover holds no web view.
    private(set) var isShowing = false
    private let directory: URL
    @ObservationIgnored private var folderWatch: DispatchSourceFileSystemObject?
    @ObservationIgnored private var exitWatches: [Int32: DispatchSourceProcess] = [:]

    init(home: URL = TrayRegistry.defaultHome()) {
        directory = home.appendingPathComponent("tray", isDirectory: true)
        watchFolder()
        refresh()
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

    func setShowing(_ showing: Bool) {
        isShowing = showing
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
        watchGuestProcesses()
    }

    /// Watches the folder for entries being added, removed or renamed. Guests write atomically, so a change always shows here.
    private func watchFolder() {
        folderWatch?.cancel()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.folderChanged() }
        }
        source.setCancelHandler { close(fd) }
        folderWatch = source
        source.resume()
    }

    private func folderChanged() {
        // If the folder itself was removed, watch the new one that is created in its place.
        if !FileManager.default.fileExists(atPath: directory.path) {
            watchFolder()
        }
        refresh()
    }

    /// Each guest's process is watched so its tab disappears the moment that process exits.
    private func watchGuestProcesses() {
        let pids = Set(guests.map(\.pid))
        for pid in exitWatches.keys where !pids.contains(pid) {
            exitWatches.removeValue(forKey: pid)?.cancel()
        }
        for pid in pids where exitWatches[pid] == nil {
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.guestExited(pid) }
            }
            exitWatches[pid] = source
            source.resume()
        }
    }

    /// The process has exited. Its tab goes now, without waiting for the process to be reaped.
    private func guestExited(_ pid: Int32) {
        exitWatches.removeValue(forKey: pid)?.cancel()
        guests.removeAll { $0.pid == pid }
    }
}
