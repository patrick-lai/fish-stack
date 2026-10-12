import XCTest
@testable import FishStack

final class PreflightTests: XCTestCase {
    private let sonoma = OperatingSystemVersion(majorVersion: 14, minorVersion: 5, patchVersion: 0)
    private let sixteenGB: UInt64 = 16 << 30

    func testAMacWithSixteenGBAndSonomaPasses() {
        XCTAssertNil(Preflight.machineProblem(macOS: sonoma, memory: sixteenGB))
    }

    func testOlderMacOSIsExplained() {
        let ventura = OperatingSystemVersion(majorVersion: 13, minorVersion: 6, patchVersion: 0)
        let message = Preflight.machineProblem(macOS: ventura, memory: sixteenGB)
        XCTAssertEqual(message, "FishStack needs macOS 14 or later. This Mac is on macOS 13.6.")
    }

    func testEightGBIsExplained() {
        let message = Preflight.machineProblem(macOS: sonoma, memory: 8 << 30)
        XCTAssertEqual(message, "FishStack needs a Mac with 16 GB of memory. This Mac has 8 GB.")
    }

    func testSetupNeedsRoomAndInternet() {
        XCTAssertNil(Preflight.setupProblem(freeDisk: 40_000_000_000, reachable: true))
        XCTAssertNotNil(Preflight.setupProblem(freeDisk: 5_000_000_000, reachable: true))
        XCTAssertNotNil(Preflight.setupProblem(freeDisk: nil, reachable: false))
    }

    func testFullDiskSaysHowMuchToFree() {
        let message = Preflight.setupProblem(freeDisk: 5_000_000_000, reachable: true)
        XCTAssertEqual(message, "FishStack needs about 12 GB free for its models. Free up about 7 GB and it will retry.")
    }
}
