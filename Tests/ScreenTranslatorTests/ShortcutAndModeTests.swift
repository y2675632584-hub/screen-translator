import XCTest
import AppKit
import Carbon
@testable import ScreenTranslator

final class ShortcutAndModeTests: XCTestCase {
    func testSingleLetterAndArbitraryModifierCombination() throws {
        let letter = try XCTUnwrap(Shortcut(event: keyEvent(code: UInt16(kVK_ANSI_K), flags: [], text: "k")))
        XCTAssertEqual(letter.keyCode, UInt32(kVK_ANSI_K))
        XCTAssertEqual(letter.modifiers, 0)
        let combination = try XCTUnwrap(Shortcut(event: keyEvent(code: UInt16(kVK_ANSI_K), flags: [.command, .control, .option, .shift], text: "K")))
        XCTAssertEqual(combination.modifiers, UInt32(cmdKey | controlKey | optionKey | shiftKey))
        XCTAssertTrue(combination.label.hasPrefix("⌃⌥⇧⌘"))
    }

    func testEscapeArrowAndFunctionKeysAreRecordable() throws {
        for (code, label) in [(kVK_Escape, "Esc"), (kVK_LeftArrow, "←"), (kVK_F12, "F12")] {
            let shortcut = try XCTUnwrap(Shortcut(event: keyEvent(code: UInt16(code), flags: [.function], text: "")))
            XCTAssertEqual(shortcut.keyLabel, label)
            XCTAssertEqual(shortcut.modifiers, 0)
        }
    }

    func testRepeatedOrModifierOnlyEventsAreNotRecorded() {
        XCTAssertNil(Shortcut(event: keyEvent(code: UInt16(kVK_ANSI_K), flags: [], text: "k", repeated: true)))
        XCTAssertNil(Shortcut(event: keyEvent(code: UInt16(kVK_Shift), flags: [.shift], text: "")))
    }

    func testShortcutMigrationAndPersistence() {
        let suite = "ScreenTranslatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("optionSpace", forKey: "shortcut")
        XCTAssertEqual(Shortcut.load(from: defaults).keyCode, UInt32(kVK_Space))
        XCTAssertEqual(Shortcut.load(from: defaults).modifiers, UInt32(optionKey))
        let chosen = Shortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey), keyLabel: "J")
        chosen.save(to: defaults)
        XCTAssertEqual(Shortcut.load(from: defaults), chosen)
    }

    @MainActor
    func testSingleModeCapturesExactlyOnce() async throws {
        var captures = 0
        try await CaptureLoop.run(mode: .single, interval: .milliseconds(1)) { captures += 1 }
        XCTAssertEqual(captures, 1)
    }

    @MainActor
    func testLiveModeRepeatsAndCancellationStopsFurtherCaptures() async throws {
        var captures = 0
        let twoFrames = expectation(description: "实时模式至少读取两帧")
        let task = Task {
            try await CaptureLoop.run(mode: .live, interval: .milliseconds(15)) {
                captures += 1
                if captures == 2 { twoFrames.fulfill() }
            }
        }
        await fulfillment(of: [twoFrames], timeout: 3)
        task.cancel()
        do {
            try await task.value
            XCTFail("实时模式应响应取消")
        } catch is CancellationError { }
        let stoppedCount = captures
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertGreaterThanOrEqual(captures, 2)
        XCTAssertEqual(captures, stoppedCount)
    }

    private func keyEvent(code: UInt16, flags: NSEvent.ModifierFlags, text: String, repeated: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                        windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
                        isARepeat: repeated, keyCode: code)!
    }
}
