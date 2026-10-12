import SwiftUI
import WebKit

/// The shared tray popover. Other apps' tabs come first, in their order, and Fish Stack's own tab is always last.
/// With no guests the popover is just Fish Stack's panel, with no tab bar.
struct TrayHost: View {
    @Bindable var server: FishServer
    let registry: TrayRegistry
    /// nil selects Fish Stack. A guest id that has gone away falls back to Fish Stack.
    @State private var selection: String?
    /// A guest page sets its own height, so the popover is as tall as the tab's content.
    @State private var guestHeight: CGFloat = 440

    private static let guestWidth: CGFloat = 388

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
        if let guest = activeGuest {
            // The guest page is loaded only while the popover is open, so each open shows fresh data and a closed tray holds no web view.
            if registry.isShowing, let url = URL(string: guest.url) {
                GuestPanel(url: url, height: $guestHeight)
                    .frame(width: Self.guestWidth, height: guestHeight)
            } else {
                Night.surface
                    .frame(width: Self.guestWidth, height: guestHeight)
            }
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
/// The page reports its height, and the panel takes that height, so the popover fits the tab's content.
struct GuestPanel: NSViewRepresentable {
    let url: URL
    @Binding var height: CGFloat

    /// Sends the page's height to Fish Stack whenever it changes.
    private static let heightScript = """
    (() => {
      const report = () => window.webkit.messageHandlers.fishStackHeight.postMessage(Math.ceil(document.body.getBoundingClientRect().height));
      new ResizeObserver(report).observe(document.body);
      report();
    })();
    """

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let content = WKUserContentController()
        content.addUserScript(WKUserScript(source: Self.heightScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        content.add(context.coordinator, name: "fishStackHeight")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = content
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.underPageBackgroundColor = NSColor(Night.surface)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let binding = $height
        context.coordinator.setHeight = { value in
            binding.wrappedValue = value
        }
        guard context.coordinator.loaded != url else { return }
        context.coordinator.loaded = url
        view.load(URLRequest(url: url))
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        var loaded: URL?
        var setHeight: ((CGFloat) -> Void)?

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let number = message.body as? NSNumber, number.doubleValue > 0 else { return }
            setHeight?(CGFloat(number.doubleValue))
        }
    }
}
