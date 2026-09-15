import SwiftUI
import AppKit

struct MenuBarQuickView: View {
    @ObservedObject var store: ScanStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Storage Cleaner").font(.headline)

            if let date = store.lastScanDate {
                Text("Last scan: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(store.items.count) items found, \(ByteFormatter.string(store.items.reduce(0) { $0 + $1.sizeBytes })) total")
                    .font(.caption)
            } else {
                Text("No scan yet").font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            Button("Open Storage Cleaner") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("o")

            Button("Quit Storage Cleaner") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 240)
    }
}
