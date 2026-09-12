import AppKit
import Foundation

/// Headless self-test: `Snipcast --probe x,y,w,h seconds` records that region of the main
/// screen (AppKit coordinates) for `seconds`, prints the finished file path, and quits.
/// Exists so the capture pipeline can be verified from a shell without driving the UI.
enum Probe {
    struct Request {
        var region: CGRect
        var seconds: Double
    }

    /// `Snipcast --edit /path/to/file.mp4` opens the review window on an existing file.
    static func editURL(_ args: [String]) -> URL? {
        guard let i = args.firstIndex(of: "--edit"), args.count > i + 1 else { return nil }
        return URL(fileURLWithPath: args[i + 1])
    }

    static func parse(_ args: [String]) -> Request? {
        guard let i = args.firstIndex(of: "--probe"), args.count > i + 2 else { return nil }
        let parts = args[i + 1].split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4, let seconds = Double(args[i + 2]) else { return nil }
        return Request(region: CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]), seconds: seconds)
    }

    @MainActor
    static func run(_ request: Request) async -> Int32 {
        guard let screen = NSScreen.main else { print("probe: no main screen"); return 2 }
        guard ScreenCapturePermission.request() else {
            print("probe: screen recording permission not granted (prompt shown if first time)")
            return 3
        }
        let recorder = ScreenRecorder()
        do {
            let url = try RecordingStore.newRecordingURL()
            print("probe: starting \(request.region) on \(screen.localizedName) → \(url.path)")
            try await recorder.start(region: request.region, on: screen, to: url, options: RecordingOptions.current())
            try await Task.sleep(for: .seconds(request.seconds))
            let finished = try await recorder.stop()
            print("probe: finished \(finished.path) \(RecordingStore.fileSize(of: finished)) bytes")
            return 0
        } catch {
            print("probe: failed \(error)")
            return 1
        }
    }
}
