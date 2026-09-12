import AppKit
import AVFoundation
import AVKit
import SwiftUI

/// Post-recording review: play, trim with AVKit's built-in handles, then send or save.
@MainActor
final class EditorModel: ObservableObject {
    let sourceURL: URL
    let player: AVPlayer
    weak var playerView: AVPlayerView?

    @Published var trimRange: CMTimeRange?
    @Published var isTrimming = false
    @Published var isExporting = false
    @Published var exportedURL: URL?
    @Published var errorMessage: String?
    @Published private(set) var sourceSize: Int64

    /// Set by the owning window controller; called once the recording has been discarded.
    var dismiss: (() -> Void)?

    init(url: URL) {
        sourceURL = url
        player = AVPlayer(url: url)
        sourceSize = RecordingStore.fileSize(of: url)
    }

    var displayedSize: Int64 { exportedURL.map(RecordingStore.fileSize(of:)) ?? sourceSize }
    var sizeText: String { RecordingStore.formattedSize(displayedSize) }
    var tooLargeForMessages: Bool { RecordingStore.exceedsMessagesLimit(displayedSize) }

    var trimText: String? {
        guard let trimRange else { return nil }
        return "Trimmed \(format(trimRange.start)) – \(format(trimRange.end))"
    }

    func beginTrim() {
        guard let playerView, playerView.canBeginTrimming else { return }
        isTrimming = true
        playerView.beginTrimming { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isTrimming = false
                guard result == .okButton, let item = self.player.currentItem else { return }
                let start = item.reversePlaybackEndTime
                let end = item.forwardPlaybackEndTime
                let duration = item.duration
                let s = start.isValid && start != .invalid ? start : .zero
                let e = end.isValid && end != .invalid && end.isNumeric ? end : duration
                let range = CMTimeRange(start: s, end: e)
                self.trimRange = (s == .zero && e == duration) ? nil : range
                self.exportedURL = nil
            }
        }
    }

    /// The file to hand out: the trimmed export when a trim exists, else the original.
    func deliverableURL() async -> URL? {
        guard let trimRange else { return sourceURL }
        if let exportedURL { return exportedURL }
        isExporting = true
        defer { isExporting = false }
        let mode: TrimExporter.Mode = UserDefaults.standard.bool(forKey: SettingsKey.preciseTrim) ? .reencode : .passthrough
        let dest = RecordingStore.trimmedURL(for: sourceURL)
        do {
            try await TrimExporter.export(source: sourceURL, range: trimRange, to: dest, mode: mode)
            exportedURL = dest
            return dest
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func sendWithMessages() {
        Task {
            guard let url = await deliverableURL() else { return }
            player.pause()
            if !ShareService.sendWithMessages(url) {
                errorMessage = "Messages isn't available for sharing on this Mac."
            }
        }
    }

    func copy() {
        Task {
            guard let url = await deliverableURL() else { return }
            ShareService.copyToPasteboard(url)
        }
    }

    func reveal() {
        Task {
            guard let url = await deliverableURL() else { return }
            ShareService.revealInFinder(url)
        }
    }

    /// Throws away a bad take: pauses playback, releases the file, moves the recording and
    /// any trimmed export to the Trash, then closes the window.
    func discard() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        do {
            try RecordingStore.discard(source: sourceURL, exported: exportedURL)
            dismiss?()
        } catch {
            player.replaceCurrentItem(with: AVPlayerItem(url: sourceURL))
            errorMessage = error.localizedDescription
        }
    }

    private func format(_ t: CMTime) -> String {
        let s = max(0, t.seconds)
        return String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
    }
}

struct PlayerViewRepresentable: NSViewRepresentable {
    @ObservedObject var model: EditorModel

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = model.player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = false
        view.allowsPictureInPicturePlayback = false
        model.playerView = view
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

struct EditorView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            PlayerViewRepresentable(model: model)
                .frame(minWidth: 480, minHeight: 270)
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.sizeText).monospacedDigit()
                        if model.tooLargeForMessages {
                            Label("Over the Messages limit", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    Text(model.trimText ?? "Untrimmed")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                Spacer()
                if model.isExporting {
                    ProgressView().controlSize(.small)
                    Text("Exporting…").foregroundStyle(.secondary).font(.callout)
                }
                Button("Move to Trash", role: .destructive) { model.discard() }
                    .disabled(model.isTrimming || model.isExporting)
                    .keyboardShortcut(.delete, modifiers: .command)
                    .help("Throw away this take. The file is moved to the Trash, so it can be recovered.")
                Button("Trim") { model.beginTrim() }
                    .disabled(model.isTrimming || model.isExporting)
                    .keyboardShortcut("t", modifiers: .command)
                Button("Copy") { model.copy() }
                    .disabled(model.isExporting)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Reveal in Finder") { model.reveal() }
                    .disabled(model.isExporting)
                Button("Send with Messages") { model.sendWithMessages() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isExporting)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(12)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private let model: EditorModel
    private var retain: EditorWindowController?

    init(url: URL) {
        model = EditorModel(url: url)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = url.lastPathComponent
        window.representedURL = url
        window.contentView = NSHostingView(rootView: EditorView(model: model))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        retain = self
        model.dismiss = { [weak self] in self?.window?.close() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        model.player.play()
    }

    func windowWillClose(_ notification: Notification) {
        model.player.pause()
        retain = nil
    }
}
