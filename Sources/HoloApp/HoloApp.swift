import AppKit
import Carbon
import SwiftUI

@MainActor
final class HoloAppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private var sleepObserver: NSObjectProtocol?

    func configure(model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        model.shortcutController.onPress = { [weak model] in model?.toggleBackgroundListening() }
        model.shortcutController.start()
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak model] _ in
            MainActor.assumeIsolated { model?.pauseListening() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        model?.pauseListening()
        model?.deskLocation.stopRequests()
        model?.shortcutController.stop()
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
    }
}

@main
struct HoloApp: App {
    @NSApplicationDelegateAdaptor(HoloAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Holo", id: "main") {
            RootView(model: model)
                .frame(minWidth: 940, minHeight: 640)
                .task {
                    appDelegate.configure(model: model)
                    await model.activateOnLaunch()
                }
        }
        .defaultSize(width: 1_040, height: 700)
        .commands {
            HoloSettingsCommands(model: model)
            CommandMenu("Holo") {
                Button(model.audio.isListening ? "Pause Listening" : "Resume Listening") {
                    model.togglePause()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Recalibrate") { model.prepareRecalibration() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.selectedProfile == nil || model.guidedSection != nil)
            }
        }
        MenuBarExtra {
            HoloMenu(model: model)
        } label: {
            Image(systemName: model.audio.isListening ? "waveform.circle.fill" : "waveform.circle")
                .accessibilityLabel(model.audio.isListening ? "Holo listening" : "Holo paused")
        }
    }
}

private struct HoloMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.audio.isListening ? "Listening for desk taps" : "Paused • microphone off")
        Button("Open Holo") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(model.audio.isListening || model.isStartingListening ? "Pause Listening" : "Listen for Taps") {
            model.toggleBackgroundListening()
            if model.selectedProfile == nil {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .disabled(model.guidedSection != nil && !model.audio.isListening && !model.isStartingListening)
        Text("\(model.shortcutController.shortcut.display) toggles listening")
        Menu("Choose Desk") {
            ForEach(model.profiles) { profile in
                Button(profile.name) { model.selectProfile(profile.id) }
            }
        }
        .disabled(model.guidedSection != nil)
        Button("Settings…") {
            model.section = .settings
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .disabled(model.guidedSection != nil)
        if model.selectedProfile == nil { Text("Calibrate Left and Right to get started") }
        if let error = model.errorMessage { Text(error) }
        Divider()
        Button("Quit Holo") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private struct HoloSettingsCommands: Commands {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                model.section = .settings
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(model.guidedSection != nil)
        }
    }
}
