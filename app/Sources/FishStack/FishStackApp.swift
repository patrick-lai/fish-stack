import AppKit
import SwiftUI

@main
struct FishStackApp: App {
    @NSApplicationDelegateAdaptor(FishStackDelegate.self) private var delegate

    init() {
        // The build script calls this to draw AppIcon.iconset from the same geometry as the menu-bar glyph.
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--render-icon"), flag + 1 < args.count {
            do {
                try AppIconArt.writeIconset(to: URL(fileURLWithPath: args[flag + 1], isDirectory: true))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
    }

    var body: some Scene {
        // SwiftUI needs a scene. This one is never inserted, so no settings or other window can open.
        MenuBarExtra(isInserted: .constant(false)) {
            EmptyView()
        } label: {
            Text("")
        }
    }
}

@MainActor
final class FishStackDelegate: NSObject, NSApplicationDelegate {
    private var server: FishServer?
    private var bar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let server = FishServer()
        server.start()
        self.server = server
        bar = StatusBarController(server: server)
    }
}
