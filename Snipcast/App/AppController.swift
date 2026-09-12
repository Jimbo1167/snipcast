import AppKit
import KeyboardShortcuts
import SwiftUI

/// Single state machine behind the menu bar item, the hotkeys, and the record → edit flow.
@MainActor
final class AppController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case selecting
        case recording(startedAt: Date)
        case finishing
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastRegion: StoredRegion? = StoredRegion.load()

    private let recorder = ScreenRecorder()
    private let selector = RegionSelector()
    private let hud = RecordingHUD()

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    init() {
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            Task { @MainActor in await self?.toggle() }
        }
        KeyboardShortcuts.onKeyUp(for: .recordLastRegion) { [weak self] in
            Task { @MainActor in await self?.recordLastRegion() }
        }
        NotificationCenter.default.addObserver(forName: .screenRecorderDidStopUnexpectedly, object: nil, queue: .main) { [weak self] note in
            let error = note.userInfo?["error"] as? any Error
            Task { @MainActor in self?.handleUnexpectedStop(error) }
        }
    }

    // MARK: Entry points

    func toggle() async {
        switch phase {
        case .idle: await startWithSelection()
        case .selecting: selector.confirm()
        case .recording: await stop()
        case .finishing: break
        }
    }

    func startWithSelection() async {
        guard phase == .idle else { return }
        guard ensurePermission() else { return }
        phase = .selecting
        let selection = await selector.select(suggested: lastRegion)
        guard phase == .selecting else { return }
        guard let selection else { phase = .idle; return }
        await beginRecording(selection)
    }

    func recordLastRegion() async {
        guard phase == .idle else { return }
        guard let last = lastRegion else { await startWithSelection(); return }
        guard ensurePermission() else { return }
        let displayID = NSScreen.screen(withDisplayID: last.displayID) != nil
            ? last.displayID
            : (NSScreen.main?.displayID ?? last.displayID)
        await beginRecording(RegionSelection(rect: last.rect, displayID: displayID))
    }

    func cancelSelection() {
        guard phase == .selecting else { return }
        selector.cancel()
    }

    func stop() async {
        guard case .recording = phase else { return }
        phase = .finishing
        hud.hide()
        do {
            let url = try await recorder.stop()
            phase = .idle
            EditorWindowController(url: url).present()
        } catch {
            phase = .idle
            presentError("Couldn't finish the recording", error)
        }
    }

    // MARK: Internals

    private func beginRecording(_ selection: RegionSelection) async {
        guard let screen = NSScreen.screen(withDisplayID: selection.displayID) ?? NSScreen.main else {
            phase = .idle
            return
        }
        // Clamp to the screen so a region dragged across a display edge stays valid.
        let region = selection.rect.intersection(screen.frame)
        guard RegionMath.isUsableSelection(region) else { phase = .idle; return }

        let options = RecordingOptions.current()
        do {
            let url = try RecordingStore.newRecordingURL()
            try await recorder.start(region: region, on: screen, to: url, options: options)
        } catch {
            phase = .idle
            presentError("Couldn't start recording", error)
            return
        }

        let started = Date()
        phase = .recording(startedAt: started)
        let stored = StoredRegion(rect: region, displayID: selection.displayID)
        stored.save()
        lastRegion = stored
        hud.show(region: region, on: screen, startedAt: started) { [weak self] in
            Task { @MainActor in await self?.stop() }
        }
    }

    private func ensurePermission() -> Bool {
        if ScreenCapturePermission.request() { return true }
        ScreenCapturePermission.showDeniedAlert()
        return false
    }

    private func handleUnexpectedStop(_ error: (any Error)?) {
        guard case .recording = phase else { return }
        hud.hide()
        phase = .idle
        if let error { presentError("Recording stopped", error) }
    }

    private func presentError(_ title: String, _ error: any Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func openRecordingsFolder() {
        if let dir = try? RecordingStore.ensureDirectory() {
            NSWorkspace.shared.open(dir)
        }
    }
}
