import KeyboardShortcuts
import SwiftUI

@main
struct SnipcastApp: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            MenuBarLabel(controller: controller)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var controller: AppController

    var body: some View {
        Image(systemName: controller.isRecording ? "record.circle.fill" : "record.circle")
            .symbolRenderingMode(controller.isRecording ? .multicolor : .monochrome)
    }
}

struct MenuContent: View {
    @ObservedObject var controller: AppController

    var body: some View {
        switch controller.phase {
        case .recording:
            Button("Stop Recording") { Task { await controller.stop() } }
                .globalKeyboardShortcut(.toggleRecording)
        case .finishing:
            Text("Finishing…")
        case .selecting:
            Button("Cancel Selection") { Task { await controller.toggle() } }
                .globalKeyboardShortcut(.toggleRecording)
        case .idle:
            Button("Record Area…") { Task { await controller.startWithSelection() } }
                .globalKeyboardShortcut(.toggleRecording)
            Button("Record Last Area") { Task { await controller.recordLastRegion() } }
                .globalKeyboardShortcut(.recordLastRegion)
                .disabled(controller.lastRegion == nil)
        }
        Divider()
        Button("Open Recordings Folder") { controller.openRecordingsFolder() }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button("Quit Snipcast") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
