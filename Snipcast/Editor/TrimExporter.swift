import AVFoundation

enum TrimExporter {
    enum Mode { case passthrough, reencode }

    /// Writes `range` of `source` to `destination`. Passthrough keeps the original encoding and
    /// snaps the cut to keyframes; re-encode is frame-accurate at the cost of a second encode.
    static func export(source: URL, range: CMTimeRange, to destination: URL, mode: Mode) async throws {
        let asset = AVURLAsset(url: source)
        let preset = mode == .passthrough ? AVAssetExportPresetPassthrough : AVAssetExportPresetHEVCHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ExportError.unsupported
        }
        session.timeRange = range
        session.shouldOptimizeForNetworkUse = true
        try await session.export(to: destination, as: .mp4)
    }

    enum ExportError: LocalizedError {
        case unsupported
        var errorDescription: String? { "This recording can't be exported with the selected preset." }
    }
}
