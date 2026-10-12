import Foundation

/// Checks that a Mac can run FishStack, and says what to fix in plain words.
enum Preflight {
    /// A 16 GB Mac reports 16 GiB; anything below 15 GiB is a smaller machine.
    static let minimumMemory: UInt64 = 15 << 30
    /// The decision model is about 8.4 GB and is converted on disk, so setup needs room for both.
    static let setupFreeDisk: Int64 = 12_000_000_000
    static let setupHosts = ["https://pypi.org/simple/", "https://github.com"]

    /// A problem that stops FishStack on any launch, or nil when the Mac can run it.
    static func machineProblem(macOS: OperatingSystemVersion, memory: UInt64) -> String? {
        if macOS.majorVersion < 14 {
            return "FishStack needs macOS 14 or later. This Mac is on macOS \(macOS.majorVersion).\(macOS.minorVersion)."
        }
        if memory < minimumMemory {
            return "FishStack needs a Mac with 16 GB of memory. This Mac has \(gibibytes(memory)) GB."
        }
        return nil
    }

    /// A problem that stops the one-time setup, or nil when setup can run now.
    static func setupProblem(freeDisk: Int64?, reachable: Bool) -> String? {
        if let freeDisk, freeDisk < setupFreeDisk {
            let missing = Double(setupFreeDisk - freeDisk) / 1_000_000_000
            return "FishStack needs about 12 GB free for its models. Free up about \(Int(missing.rounded(.up))) GB and it will retry."
        }
        if !reachable {
            return "FishStack needs an internet connection for its one-time setup. It will retry automatically."
        }
        return nil
    }

    static func freeDisk(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Any HTTP answer counts as reachable. Only a failed connection does not.
    static func canReachSetupHosts() async -> Bool {
        for host in setupHosts {
            guard let url = URL(string: host) else { return false }
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.httpMethod = "HEAD"
            do {
                _ = try await URLSession.shared.data(for: request)
            } catch {
                return false
            }
        }
        return true
    }

    private static func gibibytes(_ bytes: UInt64) -> Int {
        Int(bytes >> 30)
    }
}
