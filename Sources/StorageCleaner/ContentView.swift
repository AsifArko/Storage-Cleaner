import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ScanStore
    @State private var showConfirm = false
    @State private var containsCautionSelection = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            body_content
            Divider()
            footer
        }
        .frame(minWidth: 880, minHeight: 560)
        .confirmationDialog(
            "Permanently delete \(store.selectedIDs.count) item(s)?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                store.deleteSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    private var confirmMessage: String {
        var text = "This frees \(ByteFormatter.string(store.totalSelectedBytes)) and cannot be undone."
        if containsCautionSelection {
            text += " Some selected items are marked REVIEW — double-check the note under each before continuing."
        }
        text += " Protected files — Keychains, SSH/GPG keys, Documents, Desktop, Photos, and anything inside an app bundle or .git folder — are never touched by this app, no matter what is selected."
        return text
    }

    @ViewBuilder
    private var body_content: some View {
        if store.isScanning {
            VStack(spacing: 12) {
                ProgressView()
                Text("Scanning your disk — larger folders like DerivedData can take a little while…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text(store.lastScanDate == nil ? "No scan yet." : "Nothing found above the size threshold.")
                    .foregroundStyle(.secondary)
                Button("Scan Now") { store.scan() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(ScanCategory.allCases) { category in
                    if let categoryItems = store.groupedItems[category], !categoryItems.isEmpty {
                        Section {
                            ForEach(categoryItems) { item in
                                ItemRow(item: item, isSelected: store.selectedIDs.contains(item.id)) {
                                    store.toggle(item)
                                    containsCautionSelection = store.items.contains {
                                        store.selectedIDs.contains($0.id) && $0.tier == .caution
                                    }
                                }
                            }
                        } header: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(category.rawValue).font(.headline)
                                Text(category.blurb).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var header: some View {
        HStack {
            Text("Storage Cleaner").font(.title2).bold()
            Spacer()
            if let date = store.lastScanDate {
                Text("Last scanned \(date.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Button {
                store.scan()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(store.isScanning || store.isDeleting)
        }
        .padding()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !store.lastErrors.isEmpty {
                Text("\(store.lastErrors.count) item(s) were skipped — see console for details.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                let bytes = store.totalSelectedBytes
                Text("\(store.selectedIDs.count) selected — \(ByteFormatter.string(bytes)) would be freed")
                    .font(.subheadline)
                Spacer()
                if let freed = store.lastFreedBytes {
                    Text("Freed \(ByteFormatter.string(freed)) last run")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                Button {
                    showConfirm = true
                } label: {
                    if store.isDeleting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Delete Selected…")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(store.selectedIDs.isEmpty || store.isDeleting)
            }
        }
        .padding()
    }
}

struct ItemRow: View {
    let item: ScanItem
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayPath)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            tierBadge

            Text(ByteFormatter.string(item.sizeBytes))
                .font(.system(.body, design: .monospaced))
                .frame(width: 90, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .padding(.vertical, 3)
    }

    private var displayPath: String {
        (item.path as NSString).abbreviatingWithTildeInPath
    }

    private var tierBadge: some View {
        Group {
            switch item.tier {
            case .safe:
                badge("SAFE", color: .green)
            case .caution:
                badge("REVIEW", color: .orange)
            case .protected:
                badge("PROTECTED", color: .red)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .clipShape(Capsule())
    }
}
