import AppKit
import SwiftUI

/// The menu-bar popover. It follows CommissionAI's tray: a brand header with a status pill, a hero
/// card with the loaded-model dial and live counts, then glass sections for models, downloads and setup.
struct StatusPanel: View {
    @Bindable var server: FishServer
    @State private var source = ""
    @State private var role = "embedding"

    private static let tile = FishMark.tile(side: 32)
    private static let roles = ["decision", "embedding"]

    var body: some View {
        VStack(spacing: 12) {
            header
            hero
            if let notice = server.notice {
                NoticeRow(text: notice)
            }
            servedSection
            librarySection
            addSection
            footer
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 388)
        .background(Night.surface)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            BrandTile(image: Self.tile)
            VStack(alignment: .leading, spacing: 2) {
                Text("Fish Stack")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Night.ink)
                Text("Local models · port \(server.port)")
                    .font(.system(size: 11))
                    .foregroundStyle(Night.ink.opacity(0.45))
            }
            Spacer(minLength: 8)
            StatusPill(label: status.label, tone: status.tone, pulsing: status.pulsing)
            moreMenu
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("Open logs folder") { NSWorkspace.shared.open(server.logsURL) }
            Button("Open state folder") { NSWorkspace.shared.open(server.stateURL) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Night.ink.opacity(0.55))
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Night.fill)
                }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More")
    }

    // MARK: Hero

    private var hero: some View {
        let roles = server.health?.roles ?? [:]
        let loaded = roles.values.filter(\.loaded).count
        let total = server.health == nil ? Self.roles.count : max(roles.count, Self.roles.count)
        return HStack(alignment: .center, spacing: 18) {
            NightDial(loaded: loaded, total: total, tone: status.tone, busy: isDownloading)
            VStack(alignment: .leading, spacing: 0) {
                Text("Right now")
                    .font(.system(size: 11))
                    .foregroundStyle(Night.ink.opacity(0.42))
                Text(headline(loaded: loaded, total: total))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Night.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
                StatLine(symbol: "point.3.connected.trianglepath.dotted", label: "Decisions served", value: count(server.health?.activity?.decisions))
                NightDivider()
                StatLine(symbol: "square.grid.3x3.fill", label: "Embeddings served", value: count(server.health?.activity?.embeddings))
                NightDivider()
                StatLine(symbol: "key.horizontal.fill", label: "Live leases", value: count(server.health?.activity?.leases))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headline(loaded: Int, total: Int) -> String {
        if server.health == nil {
            return server.phase == "Stopped" ? "The model server is not running" : "Starting the model server"
        }
        if total > 0 && loaded == total {
            return "Serving \(total) models on this Mac"
        }
        return isDownloading ? "Downloading a model" : "Loading models into memory"
    }

    private func count(_ value: Int?) -> String {
        value.map(String.init) ?? "—"
    }

    // MARK: Served models

    private var servedSection: some View {
        TraySection(title: "Served models", trailing: "\(loadedCount) of \(Self.roles.count)") {
            ForEach(Array(Self.roles.enumerated()), id: \.offset) { index, name in
                if index > 0 {
                    NightDivider(inset: 52)
                }
                let info = server.health?.roles[name]
                let chip = servedChip(info)
                TrayRow(
                    symbol: symbol(for: name),
                    tone: .accent,
                    title: title(for: name),
                    detail: info?.model ?? "Waiting for the server",
                    trailing: { Chip(label: chip.label, tone: chip.tone) }
                )
            }
        }
    }

    private var loadedCount: Int {
        server.health?.roles.values.filter(\.loaded).count ?? 0
    }

    private func servedChip(_ info: RoleHealth?) -> (label: String, tone: Tone) {
        guard let info else { return ("Offline", .neutral) }
        if info.loaded { return ("Loaded", .ok) }
        switch info.state {
        case "ready": return ("Warming", .accent)
        case "not_downloaded": return ("Missing", .danger)
        default: return (info.state.replacingOccurrences(of: "_", with: " ").capitalized, .accent)
        }
    }

    // MARK: Library

    private var librarySection: some View {
        TraySection(title: "Library", trailing: server.models.isEmpty ? nil : "\(server.models.count)") {
            if server.models.isEmpty {
                Text("No models yet. Add one below.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Night.ink.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                let list = VStack(spacing: 0) {
                    ForEach(Array(server.models.enumerated()), id: \.element.id) { index, model in
                        if index > 0 {
                            NightDivider(inset: 52)
                        }
                        ModelRow(model: model, server: server)
                    }
                }
                // Keep the popover its natural height for a short library; scroll once it would grow past about four rows.
                if server.models.count > 4 {
                    ScrollView {
                        list
                    }
                    .frame(height: 260)
                } else {
                    list
                }
                if needsReset {
                    HStack(spacing: 8) {
                        Text("Not the recommended models")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Night.ink.opacity(0.45))
                        Spacer(minLength: 8)
                        GhostButton(title: "Reset to recommended", tone: .accent, symbol: "arrow.counterclockwise", height: 24) {
                            Task { await server.resetToRecommended() }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    /// True when the two active models are not both the recommended ones, so a reset would change them.
    private var needsReset: Bool {
        server.models.filter { $0.active && $0.isRecommended }.count < Self.roles.count
    }

    // MARK: Add a model

    private var addSection: some View {
        TraySection(title: "Add a model") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Night.ink.opacity(0.4))
                    TextField("Hugging Face URL or owner/name", text: $source)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Night.ink)
                        .onSubmit(submit)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Night.fill)
                }
                HStack {
                    RolePicker(selection: $role)
                    Spacer()
                    GhostButton(title: "Download", tone: .accent, symbol: "arrow.down.to.line", action: submit)
                        .disabled(trimmedSource.isEmpty)
                }
            }
            .padding(12)
        }
    }

    private var trimmedSource: String {
        source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        let text = trimmedSource
        guard !text.isEmpty else { return }
        source = ""
        Task { await server.download(source: text, role: role) }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("127.0.0.1:\(server.port) · loopback only")
                .font(.system(size: 10.5))
                .foregroundStyle(Night.ink.opacity(0.38))
            Spacer()
            GhostButton(title: "Quit", tone: .danger, symbol: "power", height: 24, quiet: true) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: Status

    private struct Status {
        let label: String
        let tone: Tone
        let pulsing: Bool
    }

    private var status: Status {
        guard let health = server.health else {
            if server.phase == "Stopped" {
                return Status(label: "Offline", tone: .danger, pulsing: false)
            }
            let installing = server.phase == "Installing the model runtime"
            return Status(label: installing ? "Installing" : "Starting", tone: .accent, pulsing: true)
        }
        let roles = health.roles.values
        if !roles.isEmpty && roles.allSatisfy(\.loaded) {
            return Status(label: "Serving", tone: .ok, pulsing: false)
        }
        if isDownloading || roles.contains(where: { $0.state == "ready" && !$0.loaded }) {
            return Status(label: "Loading", tone: .warn, pulsing: true)
        }
        return Status(label: "Needs a model", tone: .warn, pulsing: false)
    }

    private var isDownloading: Bool {
        server.models.contains { $0.isDownloading }
    }

    private func symbol(for role: String) -> String {
        role == "decision" ? "point.3.connected.trianglepath.dotted" : "square.grid.3x3.fill"
    }

    private func title(for role: String) -> String {
        role == "decision" ? "Decision" : "Embedding"
    }
}

/// One model in the library: its progress while downloading, its error, and its actions.
private struct ModelRow: View {
    let model: ModelRecord
    let server: FishServer

    var body: some View {
        TrayRow(
            symbol: model.role == "decision" ? "point.3.connected.trianglepath.dotted" : "square.grid.3x3.fill",
            tone: rowTone,
            title: model.repo,
            detail: detail,
            trailing: {
                HStack(spacing: 6) {
                    if model.isRecommended {
                        Chip(label: "Recommended", tone: .accent)
                    }
                    actions
                }
            },
            footer: { footerContent }
        )
    }

    private var rowTone: Tone {
        if model.error != nil { return .danger }
        if model.isDownloading { return .accent }
        return model.active ? .ok : .neutral
    }

    private var detail: String {
        var parts = [model.role.capitalized, stateLabel]
        if let total = model.bytesTotal, total > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    private var stateLabel: String {
        switch model.state {
        case "ready": "Ready"
        case "downloading": "Downloading"
        case "converting": "Converting"
        case "starting": "Starting"
        case "cancelled": "Cancelled"
        case "failed": "Failed"
        default: model.state.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    @ViewBuilder
    private var actions: some View {
        if model.isDownloading {
            GhostButton(title: "Cancel", tone: .danger, height: 22) { Task { await server.cancel(model) } }
        } else if model.active {
            Chip(label: "In use", tone: .ok)
        } else {
            IconButton(symbol: "trash", help: "Delete \(model.repo)", tone: .danger, size: 26) {
                Task { await server.delete(model) }
            }
        }
    }

    @ViewBuilder
    private var footerContent: some View {
        if model.isDownloading {
            ProgressBar(fraction: model.progress)
        }
        if let error = model.error {
            Text(error)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Night.coralInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The embedding/decision switch used when adding a model.
private struct RolePicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 2) {
            option("embedding", "Embedding")
            option("decision", "Decision")
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.05))
        }
    }

    private func option(_ value: String, _ label: String) -> some View {
        let selected = selection == value
        return Button {
            selection = value
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(selected ? Night.ink : Night.ink.opacity(0.45))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color.white.opacity(0.13) : Color.clear)
                }
        }
        .buttonStyle(PressableStyle())
    }
}
