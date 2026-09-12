import AppKit
import AVFoundation
import ScreenCaptureKit

enum RecorderError: LocalizedError {
    case displayNotFound
    case notRecording
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .displayNotFound: "The selected display is no longer available."
        case .notRecording: "No recording is in progress."
        case .permissionDenied: "Screen Recording permission is required."
        }
    }
}

/// Owns one ScreenCaptureKit stream and writes it straight to disk with `SCRecordingOutput`.
@MainActor
final class ScreenRecorder: NSObject {
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var finishContinuation: CheckedContinuation<Void, any Error>?
    private(set) var outputURL: URL?

    var isRecording: Bool { stream != nil }

    /// - Parameters:
    ///   - region: selection in AppKit global coordinates.
    ///   - screen: the screen that contains the region.
    func start(region: CGRect, on screen: NSScreen, to url: URL, options: RecordingOptions) async throws {
        guard ScreenCapturePermission.isGranted else { throw RecorderError.permissionDenied }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let displayID = screen.displayID,
              let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw RecorderError.displayNotFound
        }

        let geometry = RegionMath.captureGeometry(selection: region, displayFrame: screen.frame, scale: screen.backingScaleFactor)
        let ownApp = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.sourceRect = geometry.sourceRect
        config.width = Int(geometry.pixelSize.width)
        config.height = Int(geometry.pixelSize.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.frameRate))
        config.showsCursor = options.showsCursor
        config.capturesAudio = options.capturesSystemAudio
        config.excludesCurrentProcessAudio = true
        config.queueDepth = 6
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let recConfig = SCRecordingOutputConfiguration()
        recConfig.outputURL = url
        recConfig.videoCodecType = options.codec.avCodec
        recConfig.outputFileType = .mp4

        let output = SCRecordingOutput(configuration: recConfig, delegate: self)
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()

        self.stream = stream
        self.recordingOutput = output
        self.outputURL = url
    }

    /// Finalizes the file and tears the stream down. Returns the finished recording.
    func stop() async throws -> URL {
        guard let stream, let output, let url = outputURL else { throw RecorderError.notRecording }
        defer {
            self.stream = nil
            self.recordingOutput = nil
            self.outputURL = nil
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            finishContinuation = cont
            do {
                try stream.removeRecordingOutput(output)
            } catch {
                finishContinuation = nil
                cont.resume(throwing: error)
            }
        }
        try await stream.stopCapture()
        return url
    }

    private var output: SCRecordingOutput? { recordingOutput }

    private func recordingFinished(error: (any Error)?) {
        guard let cont = finishContinuation else { return }
        finishContinuation = nil
        if let error { cont.resume(throwing: error) } else { cont.resume() }
    }
}

extension ScreenRecorder: SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.recordingFinished(error: nil) }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        Task { @MainActor in self.recordingFinished(error: error) }
    }
}

extension ScreenRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            self.recordingFinished(error: error)
            NotificationCenter.default.post(name: .screenRecorderDidStopUnexpectedly, object: nil, userInfo: ["error": error])
        }
    }
}

extension Notification.Name {
    static let screenRecorderDidStopUnexpectedly = Notification.Name("ScreenRecorder.didStopUnexpectedly")
}
