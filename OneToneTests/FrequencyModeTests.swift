//
//  FrequencyModeTests.swift
//  OneToneTests
//

import SwiftUI
import XCTest
@testable import OneTone

final class FrequencyModeTests: XCTestCase {
    func testModesAreHertzNoteChord() {
        XCTAssertEqual(FrequencyMode.allCases, [.hertz, .note, .chord])
    }

    /// 既存ユーザーの見た目を変えないよう、保存値が無いときは Hz
    func testDefaultIsHertz() {
        XCTAssertEqual(FrequencyMode.default, .hertz)
    }

    /// rawValue とキーは保存値になるので変えない
    func testStorageValuesAreStable() {
        XCTAssertEqual(FrequencyMode.storageKey, "frequencyMode")
        XCTAssertEqual(FrequencyMode.hertz.rawValue, "hertz")
        XCTAssertEqual(FrequencyMode.note.rawValue, "note")
        XCTAssertEqual(FrequencyMode.chord.rawValue, "chord")
    }

    /// モード名は大文字のラベル・単位として全言語で英語のまま出す
    func testLabelsAreUntranslatedEnglish() {
        XCTAssertEqual(FrequencyMode.allCases.map(\.label), ["Hz", "NOTE", "CHORD"])
    }

    func testSummariesUseCatalogKeys() {
        XCTAssertEqual(FrequencyMode.hertz.summary.key, "Set the tone by its frequency in hertz.")
        XCTAssertEqual(FrequencyMode.note.summary.key, "Pick a single note such as A4. The knob and slider move in semitones.")
        XCTAssertEqual(FrequencyMode.chord.summary.key, "Play a major or minor chord such as C or Am.")
    }

    // MARK: - 保存（@AppStorage）

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "FrequencyModeTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testAppStorageReadsDefaultWithoutStoredValue() {
        let storage = AppStorage(wrappedValue: FrequencyMode.default, FrequencyMode.storageKey, store: defaults)
        XCTAssertEqual(storage.wrappedValue, .hertz)
    }

    func testAppStorageRestoresSavedMode() {
        defaults.set(FrequencyMode.chord.rawValue, forKey: FrequencyMode.storageKey)
        let storage = AppStorage(wrappedValue: FrequencyMode.default, FrequencyMode.storageKey, store: defaults)
        XCTAssertEqual(storage.wrappedValue, .chord)
    }

    /// 読めない保存値は既定（Hz）にする
    func testAppStorageFallsBackToDefaultForUnknownValue() {
        defaults.set("solfege", forKey: FrequencyMode.storageKey)
        let storage = AppStorage(wrappedValue: FrequencyMode.default, FrequencyMode.storageKey, store: defaults)
        XCTAssertEqual(storage.wrappedValue, .hertz)
    }

    func testResetReturnsModeToHertz() {
        defaults.set(FrequencyMode.note.rawValue, forKey: FrequencyMode.storageKey)
        ToneSettingsStore(defaults: defaults).reset()
        let storage = AppStorage(wrappedValue: FrequencyMode.default, FrequencyMode.storageKey, store: defaults)
        XCTAssertEqual(storage.wrappedValue, .hertz)
    }
}
