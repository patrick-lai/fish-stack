import SwiftUI

struct StatusMenu: View {
    @Bindable var server: FishServer
    @State private var source = ""
    @State private var role = "embedding"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let notice = server.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            servedSection
            Divider()
            downloadsSection
            Divider()
            addSection
            Divider()
            HStack {
                Spacer()
                Button("Quit Fish Stack") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private var header: some View {
        HStack {
            Label("Fish Stack", systemImage: "fish").font(.headline)
            Spacer()
            Circle()
                .fill(server.health == nil ? Color.orange : Color.green)
                .frame(width: 8, height: 8)
            Text(server.phase)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var servedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Served models").font(.subheadline.bold())
            ServedRow(title: "Decision", info: server.health?.roles["decision"])
            ServedRow(title: "Embedding", info: server.health?.roles["embedding"])
        }
    }

    private var downloadsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Downloads").font(.subheadline.bold())
            if server.models.isEmpty {
                Text("No models yet.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(server.models) { model in
                ModelRow(model: model, server: server)
            }
        }
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a model").font(.subheadline.bold())
            TextField("Hugging Face URL or owner/name", text: $source)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            HStack {
                Picker("Role", selection: $role) {
                    Text("Embedding").tag("embedding")
                    Text("Decision").tag("decision")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button("Download", action: submit)
                    .disabled(source.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func submit() {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        source = ""
        Task { await server.download(source: text, role: role) }
    }
}

private struct ServedRow: View {
    let title: String
    let info: RoleHealth?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.callout.bold())
                Spacer()
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Text(info?.model ?? "Waiting for the server")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var statusText: String {
        guard let info else { return "Offline" }
        return info.loaded ? "Loaded" : info.state.replacingOccurrences(of: "_", with: " ")
    }
}

private struct ModelRow: View {
    let model: ModelRecord
    let server: FishServer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.repo)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                actions
            }
            if model.isDownloading {
                ProgressView(value: model.progress)
            }
            if let error = model.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var detail: String {
        var parts = [model.role, model.state.replacingOccurrences(of: "_", with: " ")]
        if let total = model.bytesTotal, total > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
        }
        if model.active {
            parts.append("active")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var actions: some View {
        if model.isDownloading {
            Button("Cancel") { Task { await server.cancel(model) } }
        } else if !model.active {
            Button("Delete") { Task { await server.delete(model) } }
        }
    }
}
