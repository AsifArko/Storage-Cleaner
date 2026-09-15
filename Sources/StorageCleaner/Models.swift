import Foundation

/// How confident the app is that removing an item is safe.
///
/// `.protected` items are a hard floor: they are never shown as selectable in
/// the UI, and DeleteManager refuses to touch them even if something upstream
/// tries to pass one in anyway.
enum SafetyTier: String, Codable {
    case safe        // green  - regenerated automatically by the owning tool/app
    case caution     // yellow - regenerable but slow/costly to rebuild, or ambiguous
    case protected   // red    - never offered for deletion, no matter what
}

enum ScanCategory: String, CaseIterable, Codable, Identifiable {
    case xcodeDerivedData   = "Xcode DerivedData"
    case simulatorCaches    = "iOS Simulator Caches"
    case packageManagerCaches = "Package Manager Caches"
    case appCaches          = "Application Caches"
    case logs               = "Log Files"
    case dsStoreFiles       = ".DS_Store Files"
    case trash              = "Trash"
    case oldNodeModules     = "Old node_modules Folders"
    case dockerArtifacts    = "Docker Data"
    case devToolchains      = "Dev Toolchains"

    var id: String { rawValue }

    /// Short, plain-language explanation shown as a section subtitle.
    var blurb: String {
        switch self {
        case .xcodeDerivedData: return "Rebuilt automatically the next time you build in Xcode."
        case .simulatorCaches: return "Simulator support files Xcode regenerates on demand."
        case .packageManagerCaches: return "npm/pnpm/pip/cargo/Homebrew caches — re-downloaded automatically when needed."
        case .appCaches: return "Per-app caches under ~/Library/Caches — apps rebuild these themselves."
        case .logs: return "Historical log files with no functional purpose once written."
        case .dsStoreFiles: return "Finder metadata files, regenerated the moment you open the folder again."
        case .trash: return "Already-deleted files sitting in Trash, waiting to be purged."
        case .oldNodeModules: return "Dependency folders untouched for 90+ days — reinstall with npm/yarn/pnpm install."
        case .dockerArtifacts: return "Local Docker images, containers and volumes — re-pulled/rebuilt as needed."
        case .devToolchains: return "Installed language toolchains/runtimes you may no longer target."
        }
    }
}

struct ScanItem: Identifiable, Codable, Hashable {
    let id: UUID
    let path: String
    let sizeBytes: Int64
    let category: ScanCategory
    let tier: SafetyTier
    let reason: String

    init(path: String, sizeBytes: Int64, category: ScanCategory, tier: SafetyTier, reason: String) {
        self.id = UUID()
        self.path = path
        self.sizeBytes = sizeBytes
        self.category = category
        self.tier = tier
        self.reason = reason
    }
}
