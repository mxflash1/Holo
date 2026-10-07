import AppKit
import Carbon
import Combine

struct ListeningShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyLabel: String
    static let standard = Self(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(cmdKey), keyLabel: "H")
    var isValid: Bool {
        keyCode < 128 && !keyLabel.isEmpty
            && modifiers & UInt32(cmdKey | controlKey | optionKey) != 0
            && modifiers & ~UInt32(cmdKey | controlKey | optionKey | shiftKey) == 0
    }
    var display: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map { $0.1 }.joined() + keyLabel
    }
    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.keyLabel = keyLabel
    }
    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        var flags: UInt32 = 0
        if event.modifierFlags.contains(.command) { flags |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.control) { flags |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { flags |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { flags |= UInt32(shiftKey) }
        modifiers = flags
        let labels: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        keyLabel = labels[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
    }
}

@MainActor
final class ListeningShortcutController: ObservableObject {
    @Published private(set) var shortcut: ListeningShortcut
    @Published private(set) var recording = false
    @Published private(set) var error: String?
    var onPress: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var monitor: Any?
    private let defaults: UserDefaults
    private let storageKey = "listeningShortcut.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(ListeningShortcut.self, from: data), saved.isValid {
            shortcut = saved
        } else { shortcut = .standard }
    }

    func start() {
        guard handler == nil else { return }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<ListeningShortcutController>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { controller.onPress?() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { error = "Shortcut handling is unavailable. Use the menu bar to listen."; return }
        restoreRegistration()
    }

    private func register(_ value: ListeningShortcut) -> EventHotKeyRef? {
        var result: EventHotKeyRef?
        let status = RegisterEventHotKey(value.keyCode, value.modifiers,
            EventHotKeyID(signature: 0x484F4C4F, id: 1), GetApplicationEventTarget(), 0, &result)
        return status == noErr ? result : nil
    }

    private func restoreRegistration() {
        hotKey = register(shortcut)
        if hotKey == nil { error = "\(shortcut.display) is unavailable. Choose another shortcut, or use the menu bar." }
    }

    func change(to value: ListeningShortcut) {
        guard value.isValid else { error = "Include Command, Control, or Option with a key."; return }
        if value == shortcut && !recording && hotKey != nil { error = nil; return }
        guard let replacement = register(value) else {
            finishRecording()
            if hotKey == nil { restoreRegistration() }
            error = "That shortcut could not be registered. Your previous shortcut is unchanged."
            return
        }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        shortcut = value
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: storageKey) }
        error = nil
        finishRecording()
    }

    func beginRecording() {
        guard !recording else { return }
        error = nil
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                if event.keyCode == UInt16(kVK_Escape) { self.cancelRecording() }
                else if !event.isARepeat { self.change(to: ListeningShortcut(event: event)) }
                return true
            }
            return consumed ? nil : event
        }
    }

    private func finishRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    func cancelRecording() {
        guard recording else { return }
        finishRecording()
        error = nil
        restoreRegistration()
    }

    func stop() {
        finishRecording()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
