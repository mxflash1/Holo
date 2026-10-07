import AppKit
import Carbon
import XCTest

final class ListeningShortcutTests: XCTestCase {
    func testBareAndShiftOnlyTypingCannotBecomeGlobalShortcuts() {
        XCTAssertFalse(ListeningShortcut(keyCode: 0, modifiers: 0, keyLabel: "A").isValid)
        XCTAssertFalse(ListeningShortcut(keyCode: 0, modifiers: UInt32(shiftKey), keyLabel: "A").isValid)
        XCTAssertFalse(ListeningShortcut(keyCode: 999, modifiers: UInt32(cmdKey), keyLabel: "A").isValid)
        XCTAssertTrue(ListeningShortcut.standard.isValid)
    }

    @MainActor
    func testSavedShortcutIsRestoredWithoutRegisteringOrRecording() throws {
        let name = "HoloShortcutTest-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let desired = ListeningShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), keyLabel: "Space")
        defaults.set(try JSONEncoder().encode(desired), forKey: "listeningShortcut.v1")
        let controller = ListeningShortcutController(defaults: defaults)
        XCTAssertEqual(controller.shortcut, desired)
        XCTAssertEqual(controller.shortcut.display, "⌃⌥Space")
        XCTAssertFalse(controller.recording)
    }

    @MainActor
    func testInvalidSavedConfigurationFallsBackToDefault() throws {
        let name = "HoloShortcutTest-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(try JSONEncoder().encode(ListeningShortcut(keyCode: 0, modifiers: 0, keyLabel: "A")), forKey: "listeningShortcut.v1")
        XCTAssertEqual(ListeningShortcutController(defaults: defaults).shortcut, .standard)
    }
}
