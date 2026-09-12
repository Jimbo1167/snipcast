import AppKit
import CoreGraphics

enum ScreenCapturePermission {
    /// True if Screen Recording is already granted. Does not prompt.
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Prompts the system dialog on first call; later calls return the stored decision.
    @discardableResult
    static func request() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    static func showDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Snipcast needs Screen Recording access"
        alert.informativeText = "Turn on Snipcast under System Settings › Privacy & Security › Screen & System Audio Recording, then try again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openSystemSettings()
        }
    }
}
