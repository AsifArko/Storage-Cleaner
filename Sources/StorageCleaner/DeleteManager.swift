import Foundation

/// The only place in the app that actually removes files.
///
/// Every deletion goes through `isProtectedPath` again here, right before
/// touching disk, regardless of what the UI thinks is selected. This is
/// deliberate duplication: it means a bug in the UI's selection state, or a
/// future change to Scanner, can never bypass the safety boundary — the
/// worst case is "refuses to delete something it should have," never the
/// other way around.
enum DeleteManager {

    static let logDirectory = NSHomeDirectory() + "/Library/Application Support/StorageCleaner"
    static let logFile = logDirectory + "/deletion_log.jsonl"

    struct Result {
        let freedBytes: Int64
        let deletedPaths: [String]
        let errors: [String]
    }

    static func delete(items: [ScanItem]) -> Result {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: logDirectory, withIntermediateDirectories: true)

        var freed: Int64 = 0
        var deletedPaths: [String] = []
        var errors: [String] = []

        for item in items {
            // Hard safeguard: re-validate right before deleting. Never trust
            // a tier or path that was computed earlier and merely passed in.
            if item.tier == .protected {
                errors.append("Refused (protected tier): \(item.path)")
                continue
            }
            if ScanRules.isProtectedPath(item.path) {
                errors.append("Refused (matches protected path rule): \(item.path)")
                continue
            }

            if item.category == .dsStoreFiles {
                // Synthetic aggregate entry representing many small files.
                let home = NSHomeDirectory()
                let output = Scanner.runShell("find \"\(home)\" -name '.DS_Store' -not -path '*/Library/CloudStorage/*' -delete 2>&1")
                if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors.append("Some .DS_Store files could not be removed: \(output)")
                }
                freed += item.sizeBytes
                deletedPaths.append(item.path)
                logDeletion(path: item.path, size: item.sizeBytes)
                continue
            }

            guard fm.fileExists(atPath: item.path) else { continue }

            do {
                try fm.removeItem(atPath: item.path)
                freed += item.sizeBytes
                deletedPaths.append(item.path)
                logDeletion(path: item.path, size: item.sizeBytes)
            } catch {
                errors.append("\(item.path): \(error.localizedDescription)")
            }
        }

        return Result(freedBytes: freed, deletedPaths: deletedPaths, errors: errors)
    }

    /// Appends one line per deleted item to an audit log, so there is always
    /// a record of exactly what was removed and when — useful for figuring
    /// out later "wait, where did that folder go?"
    private static func logDeletion(path: String, size: Int64) {
        let entry: [String: Any] = [
            "path": path,
            "sizeBytes": size,
            "deletedAt": ISO8601DateFormatter().string(from: Date())
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              let line = String(data: data, encoding: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logFile), let handle = FileHandle(forWritingAtPath: logFile) {
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            if let lineData = (line + "\n").data(using: .utf8) {
                handle.write(lineData)
            }
        } else {
            try? (line + "\n").write(toFile: logFile, atomically: true, encoding: .utf8)
        }
    }
}
