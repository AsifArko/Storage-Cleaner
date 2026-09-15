import Foundation
import AppKit

/// Finds candidate items to clean, sizes them, and tags each with a safety
/// tier. Scanner never deletes anything — it only ever produces a list for
/// the UI to show and for DeleteManager to act on later.
enum Scanner {

    // MARK: - Shell helper

    /// Runs a read-only shell command and returns its stdout. Used for `du`
    /// (fast recursive sizing) and `find` (locating candidates) rather than
    /// hand-rolled recursion, which would be far slower over large trees like
    /// DerivedData or node_modules.
    static func runShell(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice // avoid pipe-buffer deadlocks on noisy stderr

        do {
            try process.run()
        } catch {
            return ""
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func sizeOf(path: String) -> Int64 {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        let output = runShell("du -sk \"\(path)\" 2>/dev/null | awk '{print $1}'")
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let kb = Int64(trimmed) {
            return kb * 1024
        }
        return 0
    }

    /// Cache / support paths that belong to applications currently running,
    /// so the scanner can flag them instead of quietly marking them "safe."
    /// Deleting a live app's active cache out from under it is exactly the
    /// kind of thing that can crash it or corrupt in-progress state.
    static func runningAppPaths() -> Set<String> {
        let home = NSHomeDirectory()
        var paths = Set<String>()
        for app in NSWorkspace.shared.runningApplications {
            if let bundleID = app.bundleIdentifier {
                paths.insert("\(home)/Library/Caches/\(bundleID)")
            }
            if let name = app.localizedName {
                paths.insert("\(home)/Library/Application Support/\(name)")
                paths.insert("\(home)/Library/Caches/\(name)")
            }
        }
        return paths
    }

    // MARK: - Main scan

    static func scan() -> [ScanItem] {
        let home = NSHomeDirectory()
        var items: [ScanItem] = []
        let runningPaths = runningAppPaths()
        let minSizeBytes: Int64 = 1_000_000 // ignore anything under ~1 MB, it isn't worth showing

        func consider(_ path: String, category: ScanCategory, tier: SafetyTier, reason: String) {
            guard FileManager.default.fileExists(atPath: path) else { return }
            guard !ScanRules.isProtectedPath(path) else { return }

            let size = sizeOf(path: path)
            guard size >= minSizeBytes else { return }

            if tier == .safe && ScanRules.matchesRunningApp(path, runningAppPaths: runningPaths) {
                items.append(ScanItem(
                    path: path,
                    sizeBytes: size,
                    category: category,
                    tier: .caution,
                    reason: reason + " An app that owns this folder is currently running, so this needs a manual look before deleting."
                ))
            } else {
                items.append(ScanItem(path: path, sizeBytes: size, category: category, tier: tier, reason: reason))
            }
        }

        // MARK: Safe — well-known regenerable caches

        consider("\(home)/Library/Developer/Xcode/DerivedData", category: .xcodeDerivedData, tier: .safe,
                  reason: "Rebuilt automatically by Xcode on your next build.")
        consider("\(home)/Library/Developer/CoreSimulator/Caches", category: .simulatorCaches, tier: .safe,
                  reason: "Simulator support cache, regenerated automatically.")
        consider("\(home)/Library/pnpm/store", category: .packageManagerCaches, tier: .safe,
                  reason: "pnpm's content-addressable package store; re-populated as needed.")
        consider("\(home)/.npm/_cacache", category: .packageManagerCaches, tier: .safe,
                  reason: "npm's download cache — equivalent to running 'npm cache clean'.")
        consider("\(home)/.cache/pip", category: .packageManagerCaches, tier: .safe,
                  reason: "pip's download cache; packages are re-downloaded as needed.")
        consider("\(home)/.cargo/registry/cache", category: .packageManagerCaches, tier: .safe,
                  reason: "Cargo's downloaded-crate cache; re-downloaded on next build.")
        consider("\(home)/.cargo/registry/src", category: .packageManagerCaches, tier: .safe,
                  reason: "Cargo's extracted-crate source cache; rebuilt from the cache above.")
        consider("\(home)/Library/Caches/Homebrew", category: .packageManagerCaches, tier: .safe,
                  reason: "Homebrew's downloaded-package cache; safe to clear (like 'brew cleanup').")
        consider("\(home)/.expo/cache", category: .packageManagerCaches, tier: .safe,
                  reason: "Expo CLI cache.")
        consider("\(home)/Library/Caches/ms-playwright", category: .packageManagerCaches, tier: .safe,
                  reason: "Playwright's downloaded browser binaries; re-downloaded via 'playwright install'.")

        // Per-app caches under ~/Library/Caches, evaluated one folder at a time.
        let cachesRoot = "\(home)/Library/Caches"
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: cachesRoot) {
            for entry in entries {
                consider("\(cachesRoot)/\(entry)", category: .appCaches, tier: .safe,
                          reason: "Per-app cache folder; the owning app rebuilds this automatically.")
            }
        }

        consider("\(home)/Library/Logs", category: .logs, tier: .safe,
                  reason: "Historical log files with no ongoing purpose.")
        consider("\(home)/.Trash", category: .trash, tier: .safe,
                  reason: "Files already deleted in Finder, waiting to be purged for good.")

        // MARK: Caution — regenerable, but slow/costly to rebuild or worth a manual look

        consider("\(home)/.rustup/toolchains", category: .devToolchains, tier: .caution,
                  reason: "Rust toolchains. Check 'rustup toolchain list' and only remove versions you no longer target.")
        consider("\(home)/Library/Containers/com.docker.docker/Data/vms", category: .dockerArtifacts, tier: .caution,
                  reason: "Docker's VM disk image — removing it deletes ALL local images, containers and volumes.")

        // .DS_Store files: harmless individually, but can add up across a deep tree.
        let dsCountOutput = runShell("find \"\(home)\" -name '.DS_Store' -not -path '*/Library/CloudStorage/*' 2>/dev/null | wc -l")
        if let count = Int(dsCountOutput.trimmingCharacters(in: .whitespacesAndNewlines)), count > 0 {
            items.append(ScanItem(
                path: "\(home) (all .DS_Store files)",
                sizeBytes: Int64(count) * 8 * 1024,
                category: .dsStoreFiles,
                tier: .safe,
                reason: "\(count) .DS_Store files found across your home folder — harmless Finder metadata, regenerated automatically."
            ))
        }

        // node_modules folders untouched for 90+ days, bounded to a reasonable depth so the scan stays fast.
        let nmOutput = runShell("find \"\(home)\" -maxdepth 6 -type d -name node_modules -not -path '*/Library/*' 2>/dev/null")
        for line in nmOutput.split(separator: "\n") {
            let path = String(line)
            let staleCheck = runShell("find \"\(path)\" -maxdepth 0 -mtime +90 2>/dev/null")
            guard !staleCheck.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            consider(path, category: .oldNodeModules, tier: .caution,
                      reason: "Not modified in 90+ days. Reinstall with npm/yarn/pnpm install if you need it again.")
        }

        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}
