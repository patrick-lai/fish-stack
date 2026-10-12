import SwiftUI
import WebKit

/// The shared tray popover. Other apps' tabs come first, in their order, and Fish Stack's own tab is always last.
/// With no guests the popover is just Fish Stack's panel, with no tab bar.
struct TrayHost: View {
    @Bindable var server: FishServer
    let registry: TrayRegistry
    /// nil selects Fish Stack. A guest id that has gone away falls back to Fish Stack.
    @State private var selection: String?

    private static let guestSize = CGSize(width: 388, height: 440)

    var body: some View {
        VStack(spacing: 0) {
            if !registry.guests.isEmpty {
                tabBar
            }
            content
        }
        .background(Night.surface)
        .environment(\.colorScheme, .dark)
    }

    private var activeGuest: TrayGuest? {
        registry.guests.first { $0.id == selection }
    }

    @ViewBuilder
    private var content: some View {
        if let guest = activeGuest, let url = URL(string: guest.url) {
            GuestPanel(url: url)
                .frame(width: Self.guestSize.width, height: Self.guestSize.height)
        } else {
            StatusPanel(server: server)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(registry.guests) { guest in
                tab(title: guest.title, selected: activeGuest?.id == guest.id) {
                    selection = guest.id
                }
            }
            tab(title: "Fish Stack", selected: activeGuest == nil) {
                selection = nil
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func tab(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(selected ? Night.ink : Night.ink.opacity(0.45))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color.white.opacity(0.13) : Color.clear)
                }
        }
        .buttonStyle(PressableStyle())
    }
}

/// Shows another app's tray page, served on loopback. Only the page's URL changes between tabs.
struct GuestPanel: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != url else { return }
        context.coordinator.loaded = url
        view.load(URLRequest(url: url))
    }

    final class Coordinator {
        var loaded: URL?
    }
}
