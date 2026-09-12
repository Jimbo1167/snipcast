import AVFoundation
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    /// One key to start a recording and, while recording, to stop it.
    static let toggleRecording = Self("toggleRecording", default: .init(.r, modifiers: [.control, .shift]))
    /// Skips region selection and records the same area as last time.
    static let recordLastRegion = Self("recordLastRegion")
}

enum VideoCodec: String, CaseIterable, Identifiable {
    case hevc, h264
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hevc: "HEVC (smaller files)"
        case .h264: "H.264 (widest compatibility)"
        }
    }
    var avCodec: AVVideoCodecType {
        switch self {
        case .hevc: .hevc
        case .h264: .h264
        }
    }
}

enum SettingsKey {
    static let codec = "codec"
    static let frameRate = "frameRate"
    static let showsCursor = "showsCursor"
    static let capturesSystemAudio = "capturesSystemAudio"
    static let preciseTrim = "preciseTrim"
    static let lastRegion = "lastRegion"
}

/// Snapshot of the user-facing capture settings, read from UserDefaults at recording start.
struct RecordingOptions: Sendable {
    var codec: VideoCodec = .hevc
    var frameRate: Int = 60
    var showsCursor = true
    var capturesSystemAudio = false

    static func current(defaults: UserDefaults = .standard) -> RecordingOptions {
        var o = RecordingOptions()
        if let raw = defaults.string(forKey: SettingsKey.codec), let c = VideoCodec(rawValue: raw) { o.codec = c }
        let fps = defaults.integer(forKey: SettingsKey.frameRate)
        if fps > 0 { o.frameRate = fps }
        if defaults.object(forKey: SettingsKey.showsCursor) != nil { o.showsCursor = defaults.bool(forKey: SettingsKey.showsCursor) }
        o.capturesSystemAudio = defaults.bool(forKey: SettingsKey.capturesSystemAudio)
        return o
    }
}

/// The last region the user recorded, so a repeat recording needs no drag.
struct StoredRegion: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var displayID: UInt32

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    init(rect: CGRect, displayID: CGDirectDisplayID) {
        x = rect.minX; y = rect.minY; width = rect.width; height = rect.height
        self.displayID = displayID
    }

    static func load(defaults: UserDefaults = .standard) -> StoredRegion? {
        guard let data = defaults.data(forKey: SettingsKey.lastRegion) else { return nil }
        return try? JSONDecoder().decode(StoredRegion.self, from: data)
    }

    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: SettingsKey.lastRegion)
        }
    }
}

struct SettingsView: View {
    @AppStorage(SettingsKey.codec) private var codec: VideoCodec = .hevc
    @AppStorage(SettingsKey.frameRate) private var frameRate = 60
    @AppStorage(SettingsKey.showsCursor) private var showsCursor = true
    @AppStorage(SettingsKey.capturesSystemAudio) private var capturesSystemAudio = false
    @AppStorage(SettingsKey.preciseTrim) private var preciseTrim = false

    var body: some View {
        Form {
            Section("Shortcuts") {
                KeyboardShortcuts.Recorder("Start / stop recording:", name: .toggleRecording)
                KeyboardShortcuts.Recorder("Record last region:", name: .recordLastRegion)
            }
            Section("Capture") {
                Picker("Codec:", selection: $codec) {
                    ForEach(VideoCodec.allCases) { Text($0.label).tag($0) }
                }
                Picker("Frame rate:", selection: $frameRate) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                Toggle("Show mouse cursor", isOn: $showsCursor)
                Toggle("Capture system audio", isOn: $capturesSystemAudio)
            }
            Section("Trimming") {
                Toggle("Frame-accurate trim (re-encodes)", isOn: $preciseTrim)
                Text("Off keeps the original encoding untouched; the cut snaps to the nearest keyframe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Recordings folder:") {
                    Button("Show in Finder") {
                        if let dir = try? RecordingStore.ensureDirectory() {
                            NSWorkspace.shared.activateFileViewerSelecting([dir])
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
