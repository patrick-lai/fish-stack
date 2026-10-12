import AppKit
import SwiftUI

/// Owns the menu-bar item and its popover, the same NSStatusItem + NSPopover pairing CommissionAI uses.
/// The glyph shows the server state: solid when serving, breathing while loading, hollow when offline.
@MainActor
final class StatusBarController: NSObject {
    private let server: FishServer
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var ticker: Timer?
    private var lastImageKey: String?

    init(server: FishServer) {
        self.server = server
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingController(rootView: StatusPanel(server: server))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Fish Stack"
        }
        refresh()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private var markState: MarkState {
        guard let health = server.health else {
            return server.phase == "Stopped" ? .offline : .loading
        }
        let roles = health.roles.values
        return !roles.isEmpty && roles.allSatisfy(\.loaded) ? .serving : .loading
    }

    private func refresh() {
        let state = markState
        let pulse: CGFloat = state == .loading ? CGFloat(0.5 + 0.5 * sin(Date().timeIntervalSinceReferenceDate * 2 * .pi / 1.6)) : 1
        let attention = server.notice != nil
        // Quantise the pulse so the image is only rebuilt when the glyph would look different.
        let key = "\(state)-\(Int(pulse * 10))-\(attention)"
        guard key != lastImageKey else { return }
        lastImageKey = key
        item.button?.image = MenuGlyph.image(state, pulse: pulse, attention: attention)
        item.button?.setAccessibilityLabel("Fish Stack, \(accessibilityState)")
    }

    private var accessibilityState: String {
        switch markState {
        case .serving: "serving"
        case .loading: "loading"
        case .offline: "offline"
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }
        if event.type == .rightMouseUp {
            showMenu(for: sender, event: event)
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showMenu(for button: NSStatusBarButton, event: NSEvent) {
        let menu = NSMenu()
        let logs = NSMenuItem(title: "Open Logs Folder", action: #selector(openLogs), keyEquivalent: "")
        logs.target = self
        menu.addItem(logs)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Fish Stack", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc private func openLogs() {
        NSWorkspace.shared.open(server.logsURL)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
