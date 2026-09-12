import AVFoundation
import CoreVideo
import Foundation
import Testing
@testable import Snipcast

/// Exercises the real AVFoundation export path against a synthetic clip written on the fly.
struct TrimExporterTests {
    private static func makeFixture(seconds: Int, fps: Int32 = 30) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snipcast-fixture-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 240,
            AVVideoCompressionPropertiesKey: [AVVideoMaxKeyFrameIntervalKey: 1], // every frame a keyframe
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320,
            kCVPixelBufferHeightKey as String: 240,
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<(seconds * Int(fps)) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            let buffer = pb!
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(frame % 255), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            #expect(adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return url
    }

    private static func duration(of url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    @Test func passthroughKeepsExactRangeWhenEveryFrameIsAKeyframe() async throws {
        let src = try await Self.makeFixture(seconds: 3)
        defer { try? FileManager.default.removeItem(at: src) }
        let dest = RecordingStore.trimmedURL(for: src)
        defer { try? FileManager.default.removeItem(at: dest) }

        let range = CMTimeRange(start: CMTime(seconds: 1, preferredTimescale: 600), duration: CMTime(seconds: 1, preferredTimescale: 600))
        try await TrimExporter.export(source: src, range: range, to: dest, mode: .passthrough)

        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(dest.lastPathComponent.hasSuffix(" trimmed.mp4"))
        let d = try await Self.duration(of: dest)
        #expect(abs(d - 1.0) < 0.05, "passthrough duration was \(d)")
    }

    @Test func reencodeProducesRequestedDuration() async throws {
        let src = try await Self.makeFixture(seconds: 3)
        defer { try? FileManager.default.removeItem(at: src) }
        let dest = RecordingStore.trimmedURL(for: src)
        defer { try? FileManager.default.removeItem(at: dest) }

        let range = CMTimeRange(start: CMTime(seconds: 0.5, preferredTimescale: 600), duration: CMTime(seconds: 2, preferredTimescale: 600))
        try await TrimExporter.export(source: src, range: range, to: dest, mode: .reencode)

        let d = try await Self.duration(of: dest)
        #expect(abs(d - 2.0) < 0.05, "re-encoded duration was \(d)")
    }
}
