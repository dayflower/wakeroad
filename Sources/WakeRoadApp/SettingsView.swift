import SwiftUI
import UniformTypeIdentifiers
import WakeRoadCore

/// Editor for user-defined watch targets. Edits a local copy and pushes it to
/// the controller on change, which persists and live-reconfigures the watcher.
struct SettingsView: View {
    @ObservedObject var controller: AppController
    @State private var rows: [CustomWatchTarget] = []
    /// Row awaiting a directory chosen from the folder importer.
    @State private var importingRowID: CustomWatchTarget.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Watch Targets")
                .font(.headline)
            Text(
                "The Mac stays awake while files with the given extensions change "
                    + "under each directory. Claude Code and Codex are set up by "
                    + "default; edit or remove them like any other. Changes apply "
                    + "immediately."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if rows.isEmpty {
                Text("No watch targets. Click Add to watch a directory.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach($rows) { $row in
                            targetRow($row)
                        }
                    }
                }
            }

            HStack {
                Button {
                    rows.append(
                        CustomWatchTarget(name: "", path: "", extensionsRaw: ""))
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 480, height: 380)
        .onAppear { rows = controller.customWatchTargets }
        .onChange(of: rows) { controller.updateCustomWatchTargets($0) }
        .fileImporter(
            isPresented: importerBinding,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result,
                let index = rows.firstIndex(where: { $0.id == importingRowID })
            {
                rows[index].path = url.path
            }
            importingRowID = nil
        }
    }

    private var importerBinding: Binding<Bool> {
        Binding(
            get: { importingRowID != nil },
            set: { if !$0 { importingRowID = nil } }
        )
    }

    @ViewBuilder
    private func targetRow(_ row: Binding<CustomWatchTarget>) -> some View {
        VStack(spacing: 6) {
            HStack {
                TextField("Name", text: row.name)
                Button {
                    rows.removeAll { $0.id == row.wrappedValue.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            HStack {
                TextField("Path (e.g. ~/projects/app)", text: row.path)
                Button("Choose…") { importingRowID = row.wrappedValue.id }
            }
            TextField("Extensions (comma-separated, e.g. md, log)", text: row.extensionsRaw)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08))
        )
    }
}
