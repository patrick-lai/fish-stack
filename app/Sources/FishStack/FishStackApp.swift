import SwiftUI

@MainActor
@main
struct FishStackApp: App {
    @State private var server: FishServer

    init() {
        let server = FishServer()
        server.start()
        _server = State(initialValue: server)
    }

    var body: some Scene {
        MenuBarExtra("Fish Stack", systemImage: "fish") {
            StatusMenu(server: server)
        }
        .menuBarExtraStyle(.window)
    }
}
