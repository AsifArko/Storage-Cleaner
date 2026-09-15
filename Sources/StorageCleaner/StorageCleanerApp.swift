import SwiftUI
import AppKit

@main
struct StorageCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ScanStore()

    var body: some Scene {
        MenuBarExtra("Storage Cleaner", systemImage: "externaldrive.badge.minus") {
            MenuBarQuickView(store: store)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Storage Cleaner", id: "main") {
            ContentView(store: store)
        }
    }
}

/// Hides the Dock icon so this behaves as a menu-bar-only app even when
/// launched with `swift run` (no .app bundle / Info.plist involved).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
