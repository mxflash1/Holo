import AppKit
import Carbon
import SwiftUI

@MainActor
final class HoloAppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private weak var model: AppModel?
    private var sleepObserver: NSObjectProtocol?

    func configure(model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<HoloAppDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                delegate.model?.toggleBackgroundListening()
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        let hotKeyID = EventHotKeyID(signature: 0x484F4C4F, id: 1)
        let hotKeyStatus = RegisterEventHotKey(UInt32(kVK_ANSI_H), UInt32(cmdKey), hotKeyID,
                                              GetApplicationEventTarget(), 0, &hotKey)
        if handlerStatus != noErr || hotKeyStatus != noErr {
            model.errorMessage = "Command–H could not be registered. Use the Holo menu bar icon to toggle listening."
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak model] _ in
            MainActor.assumeIsolated { model?.pauseListening() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        model?.pauseListening()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
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
                .frame(minWidth: 1_020, minHeight: 680)
                .task {
                    appDelegate.configure(model: model)
                    await model.activateOnLaunch()
                }
        }
        .defaultSize(width: 1_180, height: 760)
        .commands {
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
        Text("Command–H toggles listening")
        if model.selectedProfile == nil { Text("Calibrate Left and Right to get started") }
        if let error = model.errorMessage { Text(error) }
        Divider()
        Button("Quit Holo") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
