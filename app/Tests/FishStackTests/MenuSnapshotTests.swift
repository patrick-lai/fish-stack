import AppKit
import SwiftUI
import XCTest
@testable import FishStack

/// Renders the real popover against a running fishd. Opt in with FISH_STACK_SNAPSHOT=/path/to.png,
/// FISH_STACK_PORT and FISH_STACK_STATE, because it needs a live server and a menu-bar session.
@MainActor
final class MenuSnapshotTests: XCTestCase {
    func testRendersTheMenuAgainstTheRunningServer() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let output = env["FISH_STACK_SNAPSHOT"], let port = env["FISH_STACK_PORT"].flatMap(Int.init), let state = env["FISH_STACK_STATE"] else {
            throw XCTSkip("Set FISH_STACK_SNAPSHOT, FISH_STACK_PORT and FISH_STACK_STATE to render the menu.")
        }
        let server = FishServer(config: ServerConfig(port: port, stateDir: URL(fileURLWithPath: state, isDirectory: true), runtimeDir: nil))
        server.start()
        try await waitUntil(timeout: 20) { server.health != nil && !server.models.isEmpty }

        let host = NSHostingView(rootView: StatusPanel(server: server).background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: output))
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("the server did not report its models within \(Int(timeout)) seconds")
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
