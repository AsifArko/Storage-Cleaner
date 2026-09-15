import Foundation

/// The single source of truth for what this app is never allowed to touch.
///
/// Every path is checked against `isProtectedPath` twice: once when building
/// the candidate list (so protected items never even appear in the UI), and
/// again inside DeleteManager immediately before any filesystem call (so a
/// bug anywhere else in the app can't accidentally delete something on this
/// list). Treat this file as the safety boundary of the whole app — when in
/// doubt, add to this list rather than relax it.
enum ScanRules {

    /// Path suffixes (relative to the home directory) that must never be
    /// scanned or offered for deletion, under any circumstances.
    static let protectedSuffixes: [String] = [
        "/Library/Keychains",
        "/.ssh",
        "/.gnupg",
        "/.aws",
        "/.netrc",
        "/.docker/config.json",
        "/Library/Mail",
        "/Library/Messages",
        "/Library/Photos",
        "/Pictures",
        "/Documents",
        "/Desktop",
        "/Movies",
        "/Music",
        "/Library/Preferences",
        "/Library/Application Support/MobileSync",  // iOS device backups
        "/Library/CloudStorage",                      // iCloud Drive / Dropbox / etc. mounts
        "/Library/Accounts",
        "/Library/Cookies",
        "/Library/Calendars",
        "/Library/Contacts",
        "/Library/Safari",
    ]

    static func isProtectedPath(_ path: String) -> Bool {
        let home = NSHomeDirectory()

        // Never operate on anything outside the user's own home directory.
        // (No sudo, no /System, no other users' folders — full stop.)
        guard path == home || path.hasPrefix(home + "/") else { return true }

        for suffix in protectedSuffixes {
            let full = home + suffix
            if path == full || path.hasPrefix(full + "/") {
                return true
            }
        }

        // Never touch anything inside a git repository's internals.
        if path.contains("/.git/") || path.hasSuffix("/.git") {
            return true
        }

        // Never reach inside an application bundle.
        if path.contains(".app/") {
            return true
        }

        // Never touch SSH/GPG-style key material wherever it appears.
        let lowered = path.lowercased()
        if lowered.contains("id_rsa") || lowered.contains("id_ed25519") || lowered.contains(".pem") || lowered.contains(".pfx") {
            return true
        }

        return false
    }

    /// True if a currently-running application appears to own this path,
    /// meaning deleting it now could crash that app or lose unsaved state.
    /// Scanner marks matches as `.caution` instead of `.safe` and explains why.
    static func matchesRunningApp(_ path: String, runningAppPaths: Set<String>) -> Bool {
        runningAppPaths.contains(path)
    }
}
