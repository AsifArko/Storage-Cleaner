import Foundation
import SwiftUI

@MainActor
final class ScanStore: ObservableObject {
    @Published var items: [ScanItem] = []
    @Published var selectedIDs: Set<UUID> = []
    @Published var isScanning: Bool = false
    @Published var isDeleting: Bool = false
    @Published var lastFreedBytes: Int64? = nil
    @Published var lastErrors: [String] = []
    @Published var lastScanDate: Date? = nil

    var totalSelectedBytes: Int64 {
        items.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
    }

    var groupedItems: [ScanCategory: [ScanItem]] {
        Dictionary(grouping: items, by: { $0.category })
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let results = Scanner.scan()
            await MainActor.run {
                guard let self else { return }
                self.items = results
                // Only pre-select the safe tier; caution items always require a deliberate opt-in.
                self.selectedIDs = Set(results.filter { $0.tier == .safe }.map { $0.id })
                self.isScanning = false
                self.lastScanDate = Date()
                self.lastErrors = []
            }
        }
    }

    func toggle(_ item: ScanItem) {
        guard item.tier != .protected else { return }
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func deleteSelected() {
        guard !isDeleting else { return }
        let toDelete = items.filter { selectedIDs.contains($0.id) }
        guard !toDelete.isEmpty else { return }
        isDeleting = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = DeleteManager.delete(items: toDelete)
            await MainActor.run {
                guard let self else { return }
                self.lastFreedBytes = result.freedBytes
                self.lastErrors = result.errors
                let deletedPaths = Set(result.deletedPaths)
                self.items.removeAll { deletedPaths.contains($0.path) }
                self.selectedIDs = self.selectedIDs.filter { id in
                    self.items.contains { $0.id == id }
                }
                self.isDeleting = false
            }
        }
    }
}
